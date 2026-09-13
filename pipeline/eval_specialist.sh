#!/bin/bash
# Evaluate a trained specialist on the held-out briefs, through the verifier.
#   pipeline/eval_specialist.sh <s3 model.tar.gz | local model dir> <run name> [heldout briefs jsonl]
# Downloads/extracts the merged model if given an S3 URI, generates with
# transformers on the local GPU (one layer per held-out brief), verifies them,
# and prints the specialist's pass rate next to the teacher's on the same briefs.
set -euo pipefail
cd "$(dirname "$0")"
SRC=$1; RUN=$2; BRIEFS=${3:-runs/sky1/sft/heldout_briefs.jsonl}
MODELS=/home/marc/models; mkdir -p "$MODELS" runs/$RUN
if [[ "$SRC" == s3://* ]]; then
  NAME=$(basename "$(dirname "$(dirname "$SRC")")")
  DIR=$MODELS/$NAME
  if [ ! -f "$DIR/config.json" ]; then
    echo "== $(date +%T) downloading $SRC"
    mkdir -p "$DIR" && aws s3 cp "$SRC" "$DIR/model.tar.gz" --only-show-errors
    echo "== $(date +%T) extracting"; tar -xzf "$DIR/model.tar.gz" -C "$DIR" && rm "$DIR/model.tar.gz"
  fi
else
  DIR=$SRC
fi
ls "$DIR" | head -20
echo "== $(date +%T) specialist (transformers on the local GPU) writes $(wc -l < $BRIEFS) held-out layers"
PYTHONPATH=. python3.11 loop/specialist.py --segment sky --briefs "$BRIEFS" --out runs/$RUN --backend "hf:$DIR"
echo "== $(date +%T) verifying"
DISPLAY=:0 .venv/bin/python verify.py --candidates runs/$RUN/candidates.jsonl --out runs/$RUN --workers 3
.venv/bin/python - "$RUN" "$BRIEFS" <<'EOF'
import json, sys
run, briefs = sys.argv[1], sys.argv[2]
ids = {json.loads(l)["id"] for l in open(briefs)}
spec = [json.loads(l) for l in open(f"runs/{run}/verified.jsonl")]
teacher = [json.loads(l) for l in open("runs/sky1/verified.jsonl") if json.loads(l)["brief_id"] in ids]
def rate(rows): return sum(r["pass"] for r in rows) / max(1, len(rows))
def js(rows):
    v = [r["judge"].get("overall", 0) for r in rows if r.get("judge")]; return sum(v) / max(1, len(v))
print(json.dumps({"heldout_briefs": len(ids), "specialist_pass_rate": round(rate(spec), 3), "specialist_judge_mean": round(js(spec), 2),
                  "teacher_pass_rate_same_briefs": round(rate(teacher), 3), "teacher_judge_mean": round(js(teacher), 2),
                  "specialist_gate_failures": sum(1 for r in spec if r["gates"].get("static") or r["gates"].get("runtime"))}, indent=2))
json.dump({"pass_rate": rate(spec), "n": len(spec)}, open(f"runs/{run}/eval.json", "w"))
EOF
echo "== $(date +%T) done"
