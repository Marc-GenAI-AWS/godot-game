"""Processing-job wrapper: sample briefs and run the teacher (Bedrock)."""
import argparse
import subprocess
import sys

PIPE = "/opt/ml/processing/pipeline"
OUT = "/opt/ml/processing/output"

ap = argparse.ArgumentParser()
ap.add_argument("--segment", default="sky")
ap.add_argument("--n", type=int, default=200)
ap.add_argument("--k", type=int, default=2)
a = ap.parse_args()
subprocess.run([sys.executable, "-m", "pip", "install", "-q", "boto3>=1.35"], check=False)
subprocess.run([sys.executable, f"{PIPE}/briefs.py", a.segment, "--n", str(a.n), "--out", f"{OUT}/briefs.jsonl"], check=True, cwd=PIPE)
subprocess.run([sys.executable, f"{PIPE}/teacher.py", "--briefs", f"{OUT}/briefs.jsonl", "--out", OUT, "--k", str(a.k)], check=True, cwd=PIPE)
