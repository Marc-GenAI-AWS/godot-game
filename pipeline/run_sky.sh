#!/bin/bash
# Full sky data-generation run: briefs -> teacher -> verify -> revise -> verify -> SFT dataset.
set -euo pipefail
cd "$(dirname "$0")"
RUN=${1:-sky1}; N=${2:-120}; K=${3:-2}
PY=.venv/bin/python
export DISPLAY=:0
echo "== $(date) briefs"
if [ ! -f runs/$RUN/briefs.jsonl ]; then
  $PY briefs.py sky --n $N --seed 2 --out runs/$RUN/briefs.jsonl
else
  echo "using existing runs/$RUN/briefs.jsonl ($(wc -l < runs/$RUN/briefs.jsonl) briefs)"
fi
echo "== $(date) teacher (k=$K)"
$PY teacher.py --briefs runs/$RUN/briefs.jsonl --out runs/$RUN --k $K --workers 6
echo "== $(date) verify"
$PY verify.py --candidates runs/$RUN/candidates.jsonl --out runs/$RUN --workers 3
echo "== $(date) revise fails"
$PY teacher.py --revise runs/$RUN/verified.jsonl --out runs/$RUN --workers 6
echo "== $(date) verify revisions"
$PY verify.py --candidates runs/$RUN/revisions.jsonl --out runs/$RUN --name verified_rev.jsonl --workers 3
echo "== $(date) build sft"
$PY build_sft.py --verified runs/$RUN/verified.jsonl runs/$RUN/verified_rev.jsonl --out runs/$RUN/sft
echo "== $(date) done"
