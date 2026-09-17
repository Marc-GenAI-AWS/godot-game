#!/bin/bash
# Sep 15 (Marc: train a director model, straight to the 27B so it can see reference frames later).
# Step 1, the blocker: director training data. 400 scene briefs -> Opus 5 plans -> the GPU-free director
# verifier (JSON, world, every mentioned field translated to its exact trained value, sky consistent with
# the stated time and weather) -> SFT rows. No GPU: this runs alongside the scene demos.
set -uo pipefail
P=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)   # pipeline/
cd $P
export AWS_REGION=us-east-2
.venv/bin/python scene_briefs.py --n 400 --seed 21 --out runs/dir1/scene_briefs.jsonl
echo "== $(date +%T) planning 400 scene briefs with Opus 5"
.venv/bin/python director_data.py --briefs runs/dir1/scene_briefs.jsonl --out runs/dir1 \
  --model us.anthropic.claude-opus-5 --workers 6 2>&1 | grep -vE "^  scene-[0-9-]+: PASS|bedrock:" | tail -20
.venv/bin/python director_data.py --build-sft runs/dir1 --out runs/dir1/sft
echo "== $(date +%T) dir1 done"
