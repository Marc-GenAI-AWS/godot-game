"""SageMaker Pipeline: generate -> verify -> build dataset -> train -> evaluate -> register.

    pipeline/.venv/bin/python pipeline/sagemaker/pipeline_def.py --segment sky --n-briefs 200 --k 2 [--upsert] [--start]

Stages
  1. generate   Processing (CPU): briefs.py + teacher.py against Bedrock
  2. verify     Processing (GPU, custom verifier image): verify.py, judge on Bedrock
  3. build      Processing (CPU): build_sft.py -> train/val/preferences
  4. train      Training (GPU): train_sft.py (LoRA, merged)
  5. evaluate   Processing (GPU): held-out briefs through the fine-tuned model + verifier
  6. register   Model Registry, approval gated on the held-out pass rate

Requires the verifier image in ECR (pipeline/sagemaker/Dockerfile.verifier,
built on x86) and Bedrock access from the execution role. Steps 1-3 mirror the
local commands exactly, so the pipeline can be debugged on the dev box first.
"""
import argparse
import os

REGION = os.environ.get("AWS_REGION", "us-west-2")
ROLE = os.environ.get("SAGEMAKER_ROLE", "arn:aws:iam::605134472325:role/service-role/AmazonSageMaker-ExecutionRole-20260429T204999")
BUCKET = os.environ.get("SAGEMAKER_BUCKET", "sagemaker-us-west-2-605134472325")
ACCOUNT = os.environ.get("AWS_ACCOUNT", "605134472325")
PREFIX = "scene-studio"
VERIFIER_IMAGE = os.environ.get("VERIFIER_IMAGE", f"{ACCOUNT}.dkr.ecr.{REGION}.amazonaws.com/scene-verifier:latest")


def build(segment: str, n_briefs: int, k: int):
    import boto3
    import sagemaker
    from sagemaker.processing import ProcessingInput, ProcessingOutput, ScriptProcessor
    from sagemaker.pytorch import PyTorch
    from sagemaker.workflow.parameters import ParameterFloat, ParameterInteger, ParameterString
    from sagemaker.workflow.pipeline import Pipeline
    from sagemaker.workflow.pipeline_context import PipelineSession
    from sagemaker.workflow.steps import ProcessingStep, TrainingStep
    from sagemaker.workflow.condition_step import ConditionStep
    from sagemaker.workflow.conditions import ConditionGreaterThanOrEqualTo
    from sagemaker.workflow.functions import JsonGet
    from sagemaker.workflow.properties import PropertyFile
    from sagemaker.workflow.step_collections import RegisterModel

    sess = PipelineSession(boto_session=boto3.Session(region_name=REGION))
    p_n = ParameterInteger("NBriefs", default_value=n_briefs)
    p_k = ParameterInteger("CandidatesPerBrief", default_value=k)
    p_model = ParameterString("BaseModel", default_value="Qwen/Qwen2.5-Coder-7B-Instruct")
    p_min_pass = ParameterFloat("MinHeldoutPassRate", default_value=0.5)
    s3 = f"s3://{BUCKET}/{PREFIX}/{segment}/pipeline"
    src = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # pipeline/

    cpu = ScriptProcessor(image_uri=sagemaker.image_uris.retrieve("sklearn", REGION, version="1.2-1"),
                          command=["python3"], role=ROLE, instance_type="ml.m5.xlarge", instance_count=1,
                          sagemaker_session=sess, env={"AWS_REGION": REGION})
    gpu = ScriptProcessor(image_uri=VERIFIER_IMAGE, command=["python3"], role=ROLE, instance_type="ml.g5.xlarge",
                          instance_count=1, sagemaker_session=sess, env={"AWS_REGION": REGION})

    generate = ProcessingStep(
        name="Generate",
        processor=cpu,
        code=os.path.join(src, "sagemaker", "stage_generate.py"),
        inputs=[ProcessingInput(source=src, destination="/opt/ml/processing/pipeline")],
        outputs=[ProcessingOutput(output_name="candidates", source="/opt/ml/processing/output", destination=f"{s3}/candidates")],
        job_arguments=["--segment", segment, "--n", p_n.to_string(), "--k", p_k.to_string()],
    )
    verify = ProcessingStep(
        name="Verify",
        processor=gpu,
        code=os.path.join(src, "verify.py"),
        inputs=[ProcessingInput(source=generate.properties.ProcessingOutputConfig.Outputs["candidates"].S3Output.S3Uri,
                                destination="/opt/ml/processing/input")],
        outputs=[ProcessingOutput(output_name="verified", source="/opt/ml/processing/output", destination=f"{s3}/verified")],
        job_arguments=["--candidates", "/opt/ml/processing/input/candidates.jsonl", "--out", "/opt/ml/processing/output"],
    )
    build_ds = ProcessingStep(
        name="BuildDataset",
        processor=cpu,
        code=os.path.join(src, "build_sft.py"),
        inputs=[ProcessingInput(source=verify.properties.ProcessingOutputConfig.Outputs["verified"].S3Output.S3Uri,
                                destination="/opt/ml/processing/input"),
                ProcessingInput(source=src, destination="/opt/ml/processing/pipeline")],
        outputs=[ProcessingOutput(output_name="sft", source="/opt/ml/processing/output", destination=f"{s3}/sft")],
        job_arguments=["--verified", "/opt/ml/processing/input/verified.jsonl", "--out", "/opt/ml/processing/output"],
    )
    est = PyTorch(entry_point="train_sft.py", source_dir=os.path.join(src, "sagemaker"), role=ROLE,
                  framework_version="2.6", py_version="py312", instance_type="ml.g6e.2xlarge", instance_count=1,
                  hyperparameters={"model": p_model, "epochs": 3, "merge": 1}, output_path=f"{s3}/models",
                  sagemaker_session=sess, disable_profiler=True)
    train = TrainingStep(name="TrainSpecialist", estimator=est,
                         inputs={"train": build_ds.properties.ProcessingOutputConfig.Outputs["sft"].S3Output.S3Uri,
                                 "val": build_ds.properties.ProcessingOutputConfig.Outputs["sft"].S3Output.S3Uri})
    report = PropertyFile(name="EvalReport", output_name="eval", path="eval.json")
    evaluate = ProcessingStep(
        name="EvaluateHeldout",
        processor=gpu,
        code=os.path.join(src, "sagemaker", "stage_evaluate.py"),
        inputs=[ProcessingInput(source=train.properties.ModelArtifacts.S3ModelArtifacts, destination="/opt/ml/processing/model"),
                ProcessingInput(source=build_ds.properties.ProcessingOutputConfig.Outputs["sft"].S3Output.S3Uri,
                                destination="/opt/ml/processing/sft")],
        outputs=[ProcessingOutput(output_name="eval", source="/opt/ml/processing/output", destination=f"{s3}/eval")],
        job_arguments=["--segment", segment],
        property_files=[report],
    )
    register = RegisterModel(name="RegisterSpecialist", estimator=est, model_data=train.properties.ModelArtifacts.S3ModelArtifacts,
                             content_types=["application/json"], response_types=["application/json"],
                             inference_instances=["ml.g5.xlarge"], transform_instances=["ml.g5.xlarge"],
                             model_package_group_name=f"scene-{segment}-specialist", approval_status="PendingManualApproval")
    gate = ConditionStep(name="HeldoutPassRateGate",
                         conditions=[ConditionGreaterThanOrEqualTo(left=JsonGet(step_name=evaluate.name, property_file=report, json_path="pass_rate"), right=p_min_pass)],
                         if_steps=[register], else_steps=[])
    return Pipeline(name=f"scene-{segment}-specialist", parameters=[p_n, p_k, p_model, p_min_pass],
                    steps=[generate, verify, build_ds, train, evaluate, gate], sagemaker_session=sess)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--segment", default="sky")
    ap.add_argument("--n-briefs", type=int, default=200)
    ap.add_argument("--k", type=int, default=2)
    ap.add_argument("--upsert", action="store_true")
    ap.add_argument("--start", action="store_true")
    a = ap.parse_args()
    p = build(a.segment, a.n_briefs, a.k)
    import json
    print(json.dumps(json.loads(p.definition()), indent=1)[:2500], "...")
    if a.upsert:
        p.upsert(role_arn=ROLE)
        print("upserted", p.name)
    if a.start:
        ex = p.start()
        print("started", ex.arn)


if __name__ == "__main__":
    main()
