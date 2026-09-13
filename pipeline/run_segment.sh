#!/bin/bash
# Full data-generation run for one segment:
#   pipeline/run_segment.sh <segment> <run name> <n briefs> <k candidates>
# briefs -> teacher -> verify -> revise fails -> verify revisions -> SFT dataset.
set -euo pipefail
cd "$(dirname "$0")"
SEG=$1; RUN=$2; N=${3:-60}; K=${4:-2}
PY=.venv/bin/python
export DISPLAY=:0
mkdir -p runs/$RUN
echo "== $(date) briefs ($SEG)"
[ -f runs/$RUN/briefs.jsonl ] || $PY briefs.py $SEG --n $N --seed 2 --out runs/$RUN/briefs.jsonl
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
