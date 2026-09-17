#!/bin/bash
# Sep 16 (Marc: "run the sky data run"). Sky is the only segment whose data was filtered by the lenient
# Fable judge; re-judging it with today's judge left 109 examples (83 train), below the minimum. This is a
# fresh run judged correctly from the start: 144 briefs across every time-of-day x weather combination,
# two candidates each, revisions, then sky1 + sky2 (re-judged) + sky3 combined on the SAME 30 held-out
# briefs as every earlier sky eval, and the 3B retrained at 14336 tokens.
set -uo pipefail
P=/home/marc/dev/graphics-gen/pipeline
cd $P
export DISPLAY=:0 XAUTHORITY=/run/user/1000/gdm/Xauthority AWS_REGION=us-east-2 SAGEMAKER_BUCKET=amazon-sagemaker-605134472325-us-east-2-6df5g199r0fy5l
HELDOUT=runs/sky12/sft/heldout_briefs.jsonl
count() { echo "$(grep -c '"pass": true' $1 2>/dev/null) / $(grep -c . $1 2>/dev/null)"; }
mkdir -p runs/sky3
.venv/bin/python briefs.py sky --n 144 --seed 22 --out runs/sky3/briefs_all.jsonl > /dev/null
python3 - $HELDOUT <<'EOF'
import json, sys
held = {json.loads(l)["text"] for l in open(sys.argv[1])}
rows = [json.loads(l) for l in open("runs/sky3/briefs_all.jsonl")]
keep = [r for r in rows if r["text"] not in held]
open("runs/sky3/briefs.jsonl", "w").write("".join(json.dumps(r) + "\n" for r in keep))
print(len(keep), "briefs (dropped", len(rows) - len(keep), "that match a held-out brief)")
EOF
echo "== $(date +%T) sky3: $(grep -c . runs/sky3/briefs.jsonl) briefs (seed 22), judged by today's judge"
./run_segment.sh sky sky3 144 2 > runs/sky3.log 2>&1 || echo "== sky3 run_segment FAILED"
echo "== $(date +%T) sky3: first pass $(count runs/sky3/verified.jsonl), revisions $(count runs/sky3/verified_rev.jsonl)"
.venv/bin/python make_repair_pairs.py --runs sky3 --workers 2 2>&1 | grep -v "^  " | tail -3
files=""
for r in sky1 sky2 sky3; do files="$files runs/$r/verified.jsonl"; [ -s runs/$r/verified_rev.jsonl ] && files="$files runs/$r/verified_rev.jsonl"; done
.venv/bin/python build_sft.py --verified $files --out runs/sky123/sft --heldout $HELDOUT
echo "== $(date +%T) sky123 built: $(tr -d '\n ' < runs/sky123/sft/stats.json)"
MODELS="Qwen/Qwen2.5-Coder-3B-Instruct" ./train_eval_segment.sh sky sky123 > runs/train-sky123.log 2>&1 || echo "== sky123 train/eval FAILED or skipped"
grep -E 'launching|evaluating|pass_rate|judge_mean|heldout|^== ' runs/train-sky123.log | tail -12
.venv/bin/python - <<'EOF'
import json
for name in ["eval-sky-3b-rejudged", "eval-sky12-3b-len14k", "eval-sky123-3b"]:
    try: rows = [json.loads(l) for l in open(f"runs/{name}/verified.jsonl")]
    except FileNotFoundError: continue
    js = [r["judge"]["overall"] for r in rows if isinstance(r.get("judge"), dict) and isinstance(r["judge"].get("overall"), int)]
    out = []
    for w in ("beach", "street"):
        s = [r for r in rows if r["brief"].get("world") == w]
        out.append(f"{w} {sum(r['pass'] for r in s)}/{len(s)}")
    print(f"== {name}: {sum(r['pass'] for r in rows)}/{len(rows)} one-shot ({', '.join(out)}) | judge mean {sum(js)/max(1,len(js)):.2f}")
EOF
echo "== $(date +%T) sky3 run done"
