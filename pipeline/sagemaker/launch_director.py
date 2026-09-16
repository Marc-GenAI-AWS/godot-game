"""Launch the director SFT (27B Qwen3.5 VLM, LoRA) as a SageMaker training job.

    pipeline/.venv/bin/python pipeline/sagemaker/launch_director.py --data pipeline/runs/dir1/sft
    ... --max-steps 2 --dry-run    smoke job: two steps, no merge

The base model is a channel (it was copied to our bucket), not a hub download, and
the job ships its own requirements: this architecture needs transformers 5.x while
the specialists stay on 4.x.
"""
import argparse
import os
import shutil
import tempfile
import time
from pathlib import Path

import boto3

REGION = os.environ.get("AWS_REGION", "us-east-2")
ROLE = os.environ.get("SAGEMAKER_ROLE", "arn:aws:iam::605134472325:role/service-role/AmazonSageMaker-ExecutionRole-20260429T204999")
BUCKET = os.environ.get("SAGEMAKER_BUCKET", "amazon-sagemaker-605134472325-us-east-2-6df5g199r0fy5l")
PREFIX = "scene-studio/director"
BASE_S3 = f"s3://{BUCKET}/{PREFIX}/base/qwen3.8-27b/"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True, help="dir with train.jsonl / val.jsonl from director_data.py --build-sft")
    ap.add_argument("--base", default=BASE_S3)
    ap.add_argument("--instance", default="ml.g6e.12xlarge")   # 4 x L40S 48 GB: 52 GB of bf16 weights plus activations
    ap.add_argument("--epochs", type=float, default=3.0)
    ap.add_argument("--max-len", type=int, default=8192)
    ap.add_argument("--lora-r", type=int, default=16)
    ap.add_argument("--max-steps", type=int, default=-1)
    ap.add_argument("--max-hours", type=float, default=8.0)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    stamp = time.strftime("%Y%m%d-%H%M")
    job = f"scene-director-{'smoke' if a.max_steps > 0 else 'sft'}-{stamp}"
    s3_out = f"s3://{BUCKET}/{PREFIX}/models"
    hp = {"epochs": a.epochs, "lr": 1e-4, "max-len": a.max_len, "lora-r": a.lora_r, "merge": 0}
    if a.max_steps > 0:
        hp["max-steps"] = a.max_steps
    print(f"job          {job}\ninstance     {a.instance}\nbase         {a.base}\n"
          f"data         {a.data}\noutput       {s3_out}\nhyperparams  {hp}")
    if a.dry_run:
        print("dry run: nothing launched")
        return

    import sagemaker
    from sagemaker.pytorch import PyTorch
    sess = sagemaker.Session(boto3.Session(region_name=REGION))
    data = Path(a.data)
    train_uri = sess.upload_data(str(data / "train.jsonl"), bucket=BUCKET, key_prefix=f"{PREFIX}/datasets/{stamp}/train")
    val_uri = sess.upload_data(str(data / "val.jsonl"), bucket=BUCKET, key_prefix=f"{PREFIX}/datasets/{stamp}/val")
    # the job's source dir must carry requirements.txt, and the director's pins differ from the specialists'
    src = Path(tempfile.mkdtemp(prefix="director-src-"))
    here = Path(__file__).parent
    shutil.copy(here / "train_director.py", src / "train_director.py")
    shutil.copy(here / "requirements_director.txt", src / "requirements.txt")
    est = PyTorch(
        entry_point="train_director.py",
        source_dir=str(src),
        role=ROLE,
        framework_version="2.6",
        py_version="py312",
        instance_type=a.instance,
        instance_count=1,
        hyperparameters=hp,
        output_path=s3_out,
        base_job_name=job,
        use_spot_instances=False,
        max_run=int(a.max_hours * 3600),
        environment={"HF_HOME": "/tmp/hf", "TOKENIZERS_PARALLELISM": "false",
                     "PYTORCH_CUDA_ALLOC_CONF": "expandable_segments:True"},
        sagemaker_session=sess,
        disable_profiler=True,
    )
    est.fit({"train": train_uri.rsplit("/", 1)[0], "val": val_uri.rsplit("/", 1)[0], "base": a.base},
            job_name=job, wait=False)
    print(f"launched {job}; adapter will land under {s3_out}/{job}/output/model.tar.gz")


if __name__ == "__main__":
    main()
