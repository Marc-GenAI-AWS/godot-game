#!/bin/bash
# Sep 16: first data run with a LOCAL teacher - Qwen3-Coder-Next-FP8 (80 GB, 512 experts, 10 active)
# on amalia's RTX PRO 6000. The question is the exchange rate: generation is free locally, so a weaker
# teacher is fine if we simply generate more. Same 72 street-ground briefs (seed 31) as the Bedrock
# comparison run, verified identically on navani, so the survival rates are directly comparable.
# Ground is the target because it is the thinnest segment (239 examples) and the only specialist that
# does not clearly beat its teacher one-shot (32% vs 34%).
set -uo pipefail
P=/home/marc/dev/graphics-gen/pipeline
cd $P
export DISPLAY=:0 XAUTHORITY=/run/user/1000/gdm/Xauthority AWS_REGION=us-east-2
count() { echo "$(grep -c '"pass": true' $1 2>/dev/null) / $(grep -c . $1 2>/dev/null)"; }
LOCAL=local:http://192.168.4.29:8000/v1

echo "== $(date +%T) local teacher writes 2 candidates for each of 72 briefs"
.venv/bin/python teacher.py --briefs runs/ground5_local/briefs.jsonl --out runs/ground5_local \
  --backend $LOCAL --k 2 --workers 6 2>&1 | tail -3
echo "== $(date +%T) verifying (same verifier, same judge as every other run)"
.venv/bin/python verify.py --candidates runs/ground5_local/candidates.jsonl --out runs/ground5_local --segment ground --workers 3 2>&1 | tail -2
echo "== $(date +%T) local teacher first pass: $(count runs/ground5_local/verified.jsonl)"

echo "== $(date +%T) Bedrock teacher, same briefs, for the comparison"
mkdir -p runs/ground5_bedrock && cp runs/ground5_local/briefs.jsonl runs/ground5_bedrock/
.venv/bin/python teacher.py --briefs runs/ground5_bedrock/briefs.jsonl --out runs/ground5_bedrock --k 2 --workers 6 2>&1 | tail -2
.venv/bin/python verify.py --candidates runs/ground5_bedrock/candidates.jsonl --out runs/ground5_bedrock --segment ground --workers 3 2>&1 | tail -2
echo "== $(date +%T) Bedrock teacher first pass: $(count runs/ground5_bedrock/verified.jsonl)"

.venv/bin/python - <<'PY'
import json
for name, label in (("ground5_local", "local Qwen3-Coder-Next"), ("ground5_bedrock", "Claude Sonnet")):
    try: rows = [json.loads(l) for l in open(f"runs/{name}/verified.jsonl")]
    except FileNotFoundError: continue
    gates = sum(1 for r in rows if any(r["gates"].values()))
    js = [r["judge"]["overall"] for r in rows if isinstance(r.get("judge"), dict) and isinstance(r["judge"].get("overall"), int)]
    out_tok = [r["usage"].get("outputTokens") or 0 for r in rows if isinstance(r.get("usage"), dict)]
    print(f"== {label:26s} {sum(r['pass'] for r in rows):3d}/{len(rows)} passed | {gates} failed a gate | "
          f"judge mean {sum(js)/max(1,len(js)):.2f} | mean output {sum(out_tok)//max(1,len(out_tok))} tokens")
PY
echo "== $(date +%T) ground5 teacher comparison done"
