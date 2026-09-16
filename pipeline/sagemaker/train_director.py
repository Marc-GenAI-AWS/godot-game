"""SFT of the director (LoRA on the 27B Qwen3.5 VLM) inside a SageMaker training job.

Kept apart from train_sft.py on purpose: this architecture needs transformers 5.x,
while the specialist pipeline is working on transformers 4.x + TRL 0.21 and is not
worth disturbing. Text-only for now - the vision tower is frozen and unused, so a
later run can start feeding reference frames without changing the base model.

Channels: /opt/ml/input/data/{train,val}/*.jsonl and /opt/ml/input/data/base (the
model directory, copied from S3 rather than downloaded from the hub).
"""
import argparse
import json
import os

import torch
from datasets import load_dataset
from peft import LoraConfig
from transformers import AutoConfig, AutoModelForCausalLM, AutoTokenizer
from trl import SFTConfig, SFTTrainer

TEXT_MODULES = ["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"]


def load_model(path: str, gpu: bool, n_gpu: int):
    """Qwen3.5 is a conditional-generation (vision-language) class; fall back through the
    loaders transformers 5 offers for it so the job fails loudly rather than silently."""
    kwargs = {"dtype": torch.bfloat16 if gpu else torch.float32, "attn_implementation": "sdpa"}
    if n_gpu > 1:
        kwargs["device_map"] = "auto"
    errors = []
    loaders = []
    try:
        from transformers import AutoModelForImageTextToText
        loaders.append(AutoModelForImageTextToText)
    except ImportError:
        pass
    loaders.append(AutoModelForCausalLM)
    for cls in loaders:
        try:
            return cls.from_pretrained(path, **kwargs)
        except Exception as e:
            errors.append(f"{cls.__name__}: {str(e)[:200]}")
    raise RuntimeError("could not load the base model - " + " | ".join(errors))


def lora_targets(model, mode: str) -> list:
    """Adapt the text tower only: on a VLM "all-linear" would also wrap the vision
    encoder, which this run never sees."""
    if mode != "auto":
        return mode.split(",")
    names = {n.split(".")[-1] for n, m in model.named_modules()
             if isinstance(m, torch.nn.Linear) and "vision" not in n and "visual" not in n}
    hit = [t for t in TEXT_MODULES if t in names]
    if not hit:
        raise RuntimeError(f"no known text projection names among {sorted(names)[:20]}")
    return hit


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=os.environ.get("SM_CHANNEL_BASE", "base"))
    ap.add_argument("--train", default=os.environ.get("SM_CHANNEL_TRAIN", "data") + "/train.jsonl")
    ap.add_argument("--val", default=os.environ.get("SM_CHANNEL_VAL", "data") + "/val.jsonl")
    ap.add_argument("--out", default=os.environ.get("SM_MODEL_DIR", "model"))
    ap.add_argument("--epochs", type=float, default=3.0)
    ap.add_argument("--lr", type=float, default=1e-4)
    ap.add_argument("--max-len", type=int, default=8192)
    ap.add_argument("--lora-r", type=int, default=16)
    ap.add_argument("--targets", default="auto")
    ap.add_argument("--batch", type=int, default=1)
    ap.add_argument("--grad-accum", type=int, default=8)
    ap.add_argument("--merge", type=int, default=0)   # the adapter is small; merge later if it helps serving
    ap.add_argument("--max-steps", type=int, default=-1)
    a = ap.parse_args()

    import transformers
    import trl
    print(f"transformers {transformers.__version__} | trl {trl.__version__} | torch {torch.__version__}", flush=True)
    cfg = AutoConfig.from_pretrained(a.model)
    print("base:", cfg.architectures, cfg.model_type, flush=True)

    tok = AutoTokenizer.from_pretrained(a.model)
    tok.pad_token = tok.pad_token or tok.eos_token
    gpu = torch.cuda.is_available()
    n_gpu = torch.cuda.device_count() if gpu else 0
    model = load_model(a.model, gpu, n_gpu)
    if n_gpu > 1:
        model.is_parallelizable = True
        model.model_parallel = True
    model.gradient_checkpointing_enable()
    print(f"loaded on {n_gpu} gpu(s)", flush=True)

    ds = load_dataset("json", data_files={"train": a.train, "val": a.val} if os.path.exists(a.val) else {"train": a.train})

    def split(ex):
        msgs = ex["messages"]
        return {"prompt": msgs[:-1], "completion": msgs[-1:]}

    ds = ds.map(split, remove_columns=[c for c in ds["train"].column_names if c != "messages"])
    ds = ds.remove_columns(["messages"])
    targets = lora_targets(model, a.targets)
    print("lora targets:", targets, flush=True)
    sft = SFTConfig(
        output_dir=a.out + "/checkpoints",
        num_train_epochs=a.epochs,
        max_steps=a.max_steps,
        per_device_train_batch_size=a.batch,
        per_device_eval_batch_size=1,
        gradient_accumulation_steps=a.grad_accum,
        learning_rate=a.lr,
        lr_scheduler_type="cosine",
        warmup_ratio=0.05,
        logging_steps=5,
        save_strategy="no",
        bf16=gpu,
        max_length=a.max_len,
        completion_only_loss=True,
        packing=False,
        report_to=[],
        eval_strategy="epoch" if "val" in ds else "no",
    )
    lora = LoraConfig(r=a.lora_r, lora_alpha=a.lora_r * 2, lora_dropout=0.05, task_type="CAUSAL_LM",
                      target_modules=targets)
    trainer = SFTTrainer(model=model, args=sft, train_dataset=ds["train"], eval_dataset=ds.get("val"),
                         processing_class=tok, peft_config=lora)
    trainer.train()
    metrics = trainer.evaluate() if "val" in ds else {}
    print("eval", metrics, flush=True)
    os.makedirs(a.out, exist_ok=True)
    if a.merge:
        trainer.model.merge_and_unload().save_pretrained(a.out, safe_serialization=True)
    else:
        trainer.model.save_pretrained(a.out)      # adapter only: ~100 MB instead of 52 GB
    tok.save_pretrained(a.out)
    with open(os.path.join(a.out, "train_metrics.json"), "w") as f:
        json.dump({"eval": metrics, "args": vars(a), "targets": targets}, f, indent=2)


if __name__ == "__main__":
    main()
