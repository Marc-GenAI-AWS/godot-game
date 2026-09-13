"""Processing-job wrapper: run the fine-tuned specialist on the held-out briefs
inside the verifier image and write eval.json {pass_rate, mean_score}."""
import argparse
import json
import subprocess
import sys

ap = argparse.ArgumentParser()
ap.add_argument("--segment", default="sky")
a = ap.parse_args()
subprocess.run([sys.executable, "-m", "pip", "install", "-q", "vllm"], check=False)
cmd = [sys.executable, "/work/pipeline/loop/specialist.py", "--segment", a.segment,
       "--model", "/opt/ml/processing/model", "--briefs", "/opt/ml/processing/sft/heldout_briefs.jsonl",
       "--out", "/opt/ml/processing/output"]
subprocess.run(cmd, check=True, cwd="/work")
subprocess.run([sys.executable, "/work/pipeline/verify.py", "--candidates", "/opt/ml/processing/output/candidates.jsonl",
                "--out", "/opt/ml/processing/output"], check=True, cwd="/work")
rows = [json.loads(l) for l in open("/opt/ml/processing/output/verified.jsonl")]
rep = {"pass_rate": sum(r["pass"] for r in rows) / max(1, len(rows)),
       "mean_score": sum(r["score"] for r in rows) / max(1, len(rows)), "n": len(rows)}
json.dump(rep, open("/opt/ml/processing/output/eval.json", "w"))
print(rep)
