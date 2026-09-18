# Taking this project over

Scene Studio is a playable Godot 4 game whose scenery is written by small
fine-tuned models. This folder is the handover: what it is, how to run it, how
to grow it, and how to keep the models improving.

Read in this order. Each page is meant to be enough to do the thing without
asking anyone.

| Page | What you get |
|---|---|
| [1. The game](01-the-game.md) | Run it locally, understand a layer, add a segment or a whole new world |
| [2. Retraining a specialist](02-retrain-a-specialist.md) | The full data → train → evaluate loop, with the traps that cost us weeks |
| [3. Making scenes](03-make-scenes.md) | The director loop: one line of English → a playable scene |
| [4. Publishing](04-publish.md) | Export, rebuild the gallery, push to GitHub Pages |
| [5. Machines, accounts and money](05-machines-and-money.md) | Where everything runs, what it costs, what you need access to |
| [6. Where it stands](06-state-of-play.md) | Current scores, known problems, and what I would do next |

## The idea in one paragraph

A scene is built in layers — sky, ground, water, vegetation, props, characters,
crowd — and each layer is one GDScript file implementing one method. That makes
a layer small enough for a small model to write, and checkable: you can render
it and look at it. So for each layer we generate hundreds of briefs, have a
large model write two candidate layers per brief, run every candidate through a
verifier (does it parse, does it run, does it meet the numeric checks, does a
vision model agree it matches the brief), keep only the ones that pass, and
fine-tune a 3B or 7B model on those. The result is a set of specialists that
each beat the model that taught them, and a director model that turns one line
of English into a brief per layer. All of it runs on one workstation; the only
cloud pieces are the training jobs and the judge.

## The shortest possible tour

```bash
# play the current build
cd game && godot --path . -- --world=beach     # right-click in the game

# what a specialist writes: one layer, one file
less game/segments/sky/generated/v4-beach-golden.gd

# what it was asked for
python3 -c "import json;print(json.load(open('pipeline/runs/v4-beach-golden/plan.json'))['segments']['sky']['text'])"

# the contract every sky layer is written against
less pipeline/contract/sky.md
```

## Before you publish

`tools/selftest.sh` - every check in one command, about a minute, and the only gate this
project has. See
[page 6](06-state-of-play.md#how-to-tell-you-have-not-broken-anything).

## The five things most likely to trip you up

1. **Training truncation.** SFT runs at `--max-len 14336`. It was 6144 for
   weeks, which silently cut the end off 528 of 529 props examples and made
   every props and ground model look like a model-capacity problem. If a
   specialist is mysteriously bad, check the token lengths of its answers
   first. See [page 2](02-retrain-a-specialist.md#the-truncation-trap).
2. **The judge is the product.** Pass rates move when the judge or its bar
   moves, not only when the model improves. Never compare a new model to an old
   number: re-score the old model at the same bar first (it is free — verdicts
   are saved). See [page 2](02-retrain-a-specialist.md#calibrating-the-judge).
3. **Paid calls.** The teacher and the judge are Claude on Bedrock. A data run
   is tens of dollars. Nothing in the repo spends money unless you run it, but
   an orchestrator script can spend $50 while you get coffee.
4. **`pipeline/runs/` is not in git** and it is 39 GB. Every dataset, capture
   and verdict lives there. If that disk dies, the models are still in S3 but
   the evidence is gone.
5. **Godot writes to the repo when it runs.** Generated layers land in
   `game/segments/<segment>/generated/`; verifier candidates land in
   `candidates/` (ignored). Committed generated layers are what the published
   game is made of — don't delete them to "clean up".
