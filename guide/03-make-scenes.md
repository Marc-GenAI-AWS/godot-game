# 3. Making scenes

One line of English in, a playable scene out. This is the demo, and it is also
the thing customers understand in ten seconds.

## Run it

```bash
cd pipeline
export DISPLAY=:0 XAUTHORITY=/run/user/1000/gdm/Xauthority AWS_REGION=us-east-2

B="sky=hf:/home/marc/models/scene-sky-sft-20260916-1021,\
ground=hf:/home/marc/models/scene-ground-sft-20260915-1449,\
vegetation=hf:/home/marc/models/scene-vegetation-sft-20260914-2028,\
props=hf:/home/marc/models/scene-props-sft-20260915-1443"
D="hf:/home/marc/models/qwen3-8b+/home/marc/models/director-8b-adapter"

PYTHONPATH=. .venv-train/bin/python loop/director.py \
  "golden hour on a packed resort beach: dark warm tan sand, giant fan palms, \
towels thrown among the loungers and long amber light" \
  --out runs/my-scene --backend "$B" --director "$D" \
  --segments sky,ground,vegetation,props --rounds 3 --composite --composite-rounds 1
```

`pipeline/recipes/scene_demos_v4.sh` is this loop over the eight briefs behind
the published gallery — copy it and change the list.

Takes roughly 10-20 minutes per scene on one GPU, and costs only the judge
calls (the director and all four specialists are local).

## What happens

1. **The director** turns the one-liner into a brief per segment. For sky it
   writes the brief; for ground, vegetation and props it picks one trained
   value per field and `briefs.py` assembles the text, so the prompt matches
   training exactly. The local 8B director scores 47/47 on held-out briefs and
   translates 188/188 vocabulary fields exactly — better than the Claude
   teacher that trained it (80% first pass).
2. **Each specialist writes its layer**, alone, from the contract and its brief.
3. **The verifier scores each layer** on its own inside the shipped scene, and
   failures come back as a revision brief carrying the evidence, for up to
   `--rounds` rounds.
4. **The composite verifier** then judges the assembled scene as a whole — six
   views, coherence, brief match, integration, artifacts — and names which
   segments are to blame. Those segments revise from its notes and the scene is
   re-judged, up to `--composite-rounds` times.
5. **Accepted layers are installed** at
   `game/segments/<segment>/generated/<run>.gd`, and `report.json` records what
   was accepted, what was not, and a `play` link:
   `#world=beach&swap=sky:res://...;ground:res://...`

A segment with no accepted layer keeps the hand-built one. The scene is marked
`publishable` only when the final composite judgement passed.

**The director never forms its own opinion.** It routes the verifier's
evidence. That is deliberate — the loop's authority is the verifier, and a
director that argued with it would be unfalsifiable.

## Reading a run

```bash
python3 - <<'EOF'
import json
r = json.load(open("pipeline/runs/my-scene/report.json"))
print("accepted:", sorted(r["accepted"]), "| unresolved:", r["unresolved"])
print("composite:", (r.get("composite") or [{}])[-1].get("overall"),
      "| publishable:", r.get("publishable"))
print("play:", r["play"])
EOF
```

`plan.json` holds the per-segment briefs the director wrote — quote those, not
the one-liner, when you want to show what a model was actually asked for.

## Backends

`--backend` takes one value for every segment or `seg=backend` pairs:

| Form | Meaning |
|---|---|
| `teacher` | Claude on Bedrock writes the layer (a baseline, not a demo) |
| `hf:<dir>` | a local merged model directory — how the specialists run today |
| `hf:<base>+<adapter>` | base plus LoRA adapter (the director uses this form) |
| `local:http://host:8001/v1` | any OpenAI-compatible server (vLLM) |
| `endpoint:<name>` | a SageMaker endpoint |

**Never substitute the teacher for a failed specialist in a demo.** If a
specialist cannot write an accepted layer, the scene ships with the hand-built
layer and the report says so. A demo that quietly swaps Claude in is measuring
nothing.

## Writing good briefs

The model space is what it was trained on. Briefs that work name concrete,
visible things: surface colour and wear, density, how much of the sky is
covered, where the light comes from. Briefs that fail ask for objects no
contract can build — a pier, a dog, children, sunglasses. `brief_gen.py`
exists to generate briefs and validate them against what the game can actually
build; it currently covers the characters segment and is the template for the
rest.
