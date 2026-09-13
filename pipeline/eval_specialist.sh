#!/bin/bash
# Evaluate a trained specialist on the held-out briefs, through the verifier.
#   pipeline/eval_specialist.sh <s3 model.tar.gz | local model dir> <run name> [heldout briefs jsonl] [segment]
# Downloads/extracts the merged model if given an S3 URI, generates with
# transformers on the local GPU (one layer per held-out brief), verifies them,
# and prints the specialist's pass rate next to the teacher's on the same briefs.
set -euo pipefail
cd "$(dirname "$0")"
SRC=$1; RUN=$2; BRIEFS=${3:-runs/sky1/sft/heldout_briefs.jsonl}; SEG=${4:-sky}
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
./wait_gpu.sh 90
echo "== $(date +%T) specialist (transformers on the local GPU) writes $(wc -l < $BRIEFS) held-out layers"
PYTHONPATH=. .venv-train/bin/python loop/specialist.py --segment $SEG --briefs "$BRIEFS" --out runs/$RUN --backend "hf:$DIR"
echo "== $(date +%T) verifying"
DISPLAY=:0 .venv/bin/python verify.py --candidates runs/$RUN/candidates.jsonl --out runs/$RUN --workers 3
echo "== $(date +%T) specialist revises its fails once (the loop's behaviour)"
./wait_gpu.sh 60
PYTHONPATH=. .venv-train/bin/python loop/specialist.py --segment $SEG --revise runs/$RUN/verified.jsonl --out runs/$RUN --backend "hf:$DIR"
DISPLAY=:0 .venv/bin/python verify.py --candidates runs/$RUN/revisions.jsonl --out runs/$RUN --name verified_rev.jsonl --workers 3
.venv/bin/python - "$RUN" "$BRIEFS" "$SEG" <<'EOF2'
import json, sys, glob
run, briefs, seg = sys.argv[1], sys.argv[2], sys.argv[3]
ids = {json.loads(l)["id"] for l in open(briefs)}
first = [json.loads(l) for l in open(f"runs/{run}/verified.jsonl")]
rev = {}
for l in open(f"runs/{run}/verified_rev.jsonl"):
    r = json.loads(l); rev[r["candidate"][:-1]] = r
teacher = [json.loads(l) for f in glob.glob(f"runs/{seg}*[0-9]/verified.jsonl") for l in open(f) if json.loads(l)["brief_id"] in ids]
def rate(rows): return round(sum(r["pass"] for r in rows) / max(1, len(rows)), 3)
def js(rows):
    v = [r["judge"].get("overall", 0) for r in rows if r.get("judge")]; return round(sum(v) / max(1, len(v)), 2)
after = [r for r in first if r["pass"] or rev.get(r["candidate"], {}).get("pass")]
rep = {"heldout_briefs": len(ids), "one_shot_pass_rate": rate(first), "after_one_revision_pass_rate": round(len(after) / max(1, len(first)), 3),
       "judge_mean_one_shot": js(first), "gate_failures_one_shot": sum(1 for r in first if any(r["gates"].values())),
       "gate_failures_revisions": sum(1 for r in rev.values() if any(r["gates"].values())),
       "teacher_one_shot_pass_rate_same_briefs": rate(teacher), "teacher_judge_mean": js(teacher)}
print(json.dumps(rep, indent=2))
json.dump(rep, open(f"runs/{run}/eval.json", "w"), indent=2)
EOF2
echo "== $(date +%T) done"
