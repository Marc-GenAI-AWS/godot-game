"""SFT of one specialist (LoRA on an open code model) - runs inside a SageMaker
PyTorch training job (see launch_sft.py) or locally with the same arguments.

Input channels: /opt/ml/input/data/train/train.jsonl, /opt/ml/input/data/val/val.jsonl
Output: /opt/ml/model (merged weights + tokenizer, ready for vLLM / TGI).
"""
import argparse
import json
import os

import torch
from datasets import load_dataset
from peft import LoraConfig
from transformers import AutoModelForCausalLM, AutoTokenizer
from trl import SFTConfig, SFTTrainer


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=os.environ.get("BASE_MODEL", "Qwen/Qwen2.5-Coder-7B-Instruct"))
    ap.add_argument("--train", default=os.environ.get("SM_CHANNEL_TRAIN", "data") + "/train.jsonl")
    ap.add_argument("--val", default=os.environ.get("SM_CHANNEL_VAL", "data") + "/val.jsonl")
    ap.add_argument("--out", default=os.environ.get("SM_MODEL_DIR", "model"))
    ap.add_argument("--epochs", type=float, default=3.0)
    ap.add_argument("--lr", type=float, default=1.5e-4)
    ap.add_argument("--max-len", type=int, default=6144)
    ap.add_argument("--lora-r", type=int, default=32)
    ap.add_argument("--batch", type=int, default=1)
    ap.add_argument("--grad-accum", type=int, default=8)
    ap.add_argument("--merge", type=int, default=1)
    a = ap.parse_args()

    tok = AutoTokenizer.from_pretrained(a.model)
    tok.pad_token = tok.pad_token or tok.eos_token
    model = AutoModelForCausalLM.from_pretrained(a.model, torch_dtype=torch.bfloat16, attn_implementation="sdpa")
    model.gradient_checkpointing_enable()

    ds = load_dataset("json", data_files={"train": a.train, "val": a.val} if os.path.exists(a.val) else {"train": a.train})
    cfg = SFTConfig(
        output_dir=a.out + "/checkpoints",
        num_train_epochs=a.epochs,
        per_device_train_batch_size=a.batch,
        gradient_accumulation_steps=a.grad_accum,
        learning_rate=a.lr,
        lr_scheduler_type="cosine",
        warmup_ratio=0.05,
        logging_steps=5,
        save_strategy="no",
        bf16=True,
        max_length=a.max_len,
        assistant_only_loss=True,      # loss on the layer file, not the contract
        packing=False,
        report_to=[],
        eval_strategy="epoch" if "val" in ds else "no",
    )
    lora = LoraConfig(r=a.lora_r, lora_alpha=a.lora_r * 2, lora_dropout=0.05, task_type="CAUSAL_LM",
                      target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"])
    trainer = SFTTrainer(model=model, args=cfg, train_dataset=ds["train"], eval_dataset=ds.get("val"),
                         processing_class=tok, peft_config=lora)
    trainer.train()
    metrics = trainer.evaluate() if "val" in ds else {}
    print("eval", metrics)
    os.makedirs(a.out, exist_ok=True)
    if a.merge:
        merged = trainer.model.merge_and_unload()
        merged.save_pretrained(a.out, safe_serialization=True)
    else:
        trainer.model.save_pretrained(a.out)
    tok.save_pretrained(a.out)
    with open(os.path.join(a.out, "train_metrics.json"), "w") as f:
        json.dump({"eval": metrics, "args": vars(a)}, f, indent=2)


if __name__ == "__main__":
    main()
