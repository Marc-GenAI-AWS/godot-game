"""Evaluate a trained director on held-out scene briefs, through the director verifier.

    PYTHONPATH=. .venv-train/bin/python eval_director.py --model ~/models/qwen3-8b \
        --adapter ~/models/director-8b-adapter --briefs runs/dir1/sft/heldout_briefs.jsonl --out runs/eval-dir8b

Same grading as the training data: the plan must parse, cover every segment, pick the world the brief
describes, translate each phrase into the exact trained value, and keep the sky consistent with the stated
time and weather. The teacher's own first-pass rate on this task was 80% (321 of 400).
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent / "loop"))

from common import parse_json, read_jsonl, write_jsonl  # noqa: E402
from director import system_prompt  # noqa: E402
from director_data import SEGMENTS, check_plan  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True, help="base model directory")
    ap.add_argument("--adapter", help="LoRA adapter directory (omit for the base model)")
    ap.add_argument("--briefs", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--segments", default=",".join(SEGMENTS))
    ap.add_argument("--max-new-tokens", type=int, default=2000)
    a = ap.parse_args()

    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer
    segments = a.segments.split(",")
    system = system_prompt(segments)
    rows = read_jsonl(a.briefs)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)

    tok = AutoTokenizer.from_pretrained(a.model)
    model = AutoModelForCausalLM.from_pretrained(a.model, torch_dtype=torch.bfloat16, device_map="cuda")
    if a.adapter:
        from peft import PeftModel
        model = PeftModel.from_pretrained(model, a.adapter)
    model.eval()
    print(f"loaded {a.model}" + (f" + {a.adapter}" if a.adapter else ""), flush=True)

    results = []
    for i, r in enumerate(rows, 1):
        msgs = [{"role": "system", "content": system}, {"role": "user", "content": "Scene brief: " + r["text"]}]
        enc = tok.apply_chat_template(msgs, add_generation_prompt=True, return_tensors="pt",
                                      enable_thinking=False).to(model.device)
        with torch.no_grad():
            gen = model.generate(enc, max_new_tokens=a.max_new_tokens, do_sample=False,
                                 pad_token_id=tok.pad_token_id or tok.eos_token_id)
        text = tok.decode(gen[0][enc.shape[1]:], skip_special_tokens=True)
        row = {"id": r["id"], "scene_brief": r["text"], "intent": r["intent"], "segments": segments, "reply": text}
        try:
            plan = parse_json(text)
            problems = check_plan(plan, r["intent"], segments)
            row.update({"plan": plan, "problems": problems, "pass": not problems})
        except Exception as e:
            row.update({"plan": None, "problems": [f"reply is not JSON ({str(e)[:80]})"], "pass": False})
        results.append(row)
        print(f"[{i}/{len(rows)}] {r['id']}: {'PASS' if row['pass'] else 'fail - ' + '; '.join(row['problems'])[:100]}", flush=True)

    write_jsonl(out / "planned.jsonl", results)
    ok = sum(1 for r in results if r["pass"])
    rep = {"briefs": len(results), "pass_rate": round(ok / max(1, len(results)), 3),
           "teacher_first_pass_rate": 0.803,
           "worlds_right": round(sum(1 for r in results if (r.get("plan") or {}).get("world") == r["intent"]["world"]) / max(1, len(results)), 3),
           "json_valid": round(sum(1 for r in results if r.get("plan")) / max(1, len(results)), 3)}
    print(json.dumps(rep, indent=2))
    (out / "eval.json").write_text(json.dumps(rep, indent=2))


if __name__ == "__main__":
    main()
