#!/bin/bash
# Sep 16 (Marc: "produce the 8 scenes"). The first run where every model that plans or writes a scene is
# local and fine-tuned: the 8B director (trained this morning) plans, and four specialists write every
# layer - including sky, whose new model beats its teacher for the first time. Claude only judges.
# Eight scenes chosen for variety, the way the anchor page showed off the range: four beach, four street,
# across dawn, morning, noon, golden hour, afternoon, dusk, overcast and hazy.
set -uo pipefail
P=/home/marc/dev/graphics-gen/pipeline
cd $P
export DISPLAY=:0 XAUTHORITY=/run/user/1000/gdm/Xauthority AWS_REGION=us-east-2
B="sky=hf:/home/marc/models/scene-sky-sft-20260916-1021,ground=hf:/home/marc/models/scene-ground-sft-20260915-1449,vegetation=hf:/home/marc/models/scene-vegetation-sft-20260914-2028,props=hf:/home/marc/models/scene-props-sft-20260915-1443"
D="hf:/home/marc/models/qwen3-8b+/home/marc/models/director-8b-adapter"
declare -a NAMES=(v4-beach-noon v4-beach-dawn v4-beach-golden v4-beach-overcast
                  v4-street-morning v4-street-dusk v4-street-overcast v4-street-hazy)
declare -a BRIEFS=(
  "a clear tropical noon on the beach: golden sand with a wide shiny wet band, tall fan palms along the promenade, rows of loungers under bright striped umbrellas"
  "dawn on a quiet shoreline: pale coral sand still dark from the tide, low scrubby coastal planting, a few loungers stacked and almost no clutter, the sun barely up over the sea"
  "golden hour on a packed resort beach: dark warm tan sand, giant fan palms, towels thrown among the loungers and umbrellas over almost every one, long amber light"
  "an overcast afternoon on a grey volcanic beach: flat light with no shadows, dry sun-bleached planting, only a few umbrellas out and little clutter"
  "a bright morning on a suburban street: fresh black tarmac with a single dashed white line, big mature shade trees, lush green lawns, lamps and bins along the kerb"
  "dusk on a quiet residential street: worn grey asphalt, dry yellowing lawns, young leafy trees, power poles with sagging wires and a stop sign at the corner"
  "an overcast morning on a manicured palm-lined street: patched and faded road, grey granite kerbs, unbroken clipped hedges along every fence, black lamps and blue bins"
  "a hazy afternoon on a residential street: sun-baked brownish road with double yellow lines, manicured verges, cracked sidewalk slabs, a bench by the crossing and a mailbox"
)
for i in "${!NAMES[@]}"; do
  echo "== $(date +%T) [$((i + 1))/8] ${NAMES[$i]}: ${BRIEFS[$i]}"
  PYTHONPATH=. .venv-train/bin/python loop/director.py "${BRIEFS[$i]}" --out runs/${NAMES[$i]} --backend "$B" \
    --director "$D" --segments sky,ground,vegetation,props --rounds 3 --composite --composite-rounds 1 \
    > runs/${NAMES[$i]}.log 2>&1
  grep -v Warning runs/${NAMES[$i]}.log | grep -E '^director|director fix|round [0-9]|composite round' | cut -c1-170
  python3 -c "
import json
r = json.load(open('runs/${NAMES[$i]}/report.json'))
c = (r.get('composite') or [{}])[-1]
print('  accepted:', sorted(r['accepted']), '| unresolved:', r['unresolved'], '| composite', c.get('overall'), '| publishable:', r.get('publishable'))
" 2>/dev/null || echo "  no report"
done
echo "== $(date +%T) all 8 scenes done"
python3 - <<'PY'
import json
from pathlib import Path
names = "v4-beach-noon v4-beach-dawn v4-beach-golden v4-beach-overcast v4-street-morning v4-street-dusk v4-street-overcast v4-street-hazy".split()
tot = {}
for n in names:
    p = Path("runs") / n / "report.json"
    if not p.exists():
        print(f"{n}: no report"); continue
    r = json.loads(p.read_text())
    c = (r.get("composite") or [{}])[-1]
    for s in r["accepted"]:
        tot[s] = tot.get(s, 0) + 1
    print(f"{n:22s} accepted {len(r['accepted'])}/4 {sorted(r['accepted'])} | composite {c.get('overall')} | publishable {r.get('publishable')}")
print("\nper segment across the 8 scenes:", {k: f"{v}/8" for k, v in sorted(tot.items())})
PY
