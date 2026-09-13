# Specialist pipeline

The design in `design/specialist-models.md`, made runnable: brief sampler,
teacher generation on Bedrock, the verifier (gates, checks, native capture,
Claude judge), the SFT dataset builder, SageMaker training and pipeline
definitions, and the director loop that assembles a scene from specialists.

The first segment is **sky**. Everything is segment-keyed (`pipeline/contract/
<segment>.md`, `pipeline/rubrics/<segment>.md`, `SEGMENTS` in `common.py`,
`CHECKS` in `verify.py`, `SAMPLERS` in `briefs.py`), so adding a segment is
one entry in each.

```
pipeline/
  common.py            paths, Bedrock Converse helper, segment table
  briefs.py            brief sampler (time of day x weather x palette words)
  teacher.py           Claude writes k candidates per brief; --revise re-writes fails from evidence
  verify.py            static gate -> runtime gate -> native capture -> checks -> judge -> score/pass/evidence
  build_sft.py         passes -> train/val chat JSONL; fails -> preference pairs; held-out briefs
  contract/sky.md      what the specialist may assume (given as the system prompt at train and test time)
  rubrics/sky.md       the judge's per-segment rubric
  loop/specialist.py   one call = one layer; backends: teacher | local:<vLLM url> | endpoint:<SageMaker>
  loop/director.py     scene brief -> per-segment briefs -> specialists -> verify -> revise -> install
  sagemaker/
    train_sft.py       TRL SFT + LoRA (merged output), runs in a PyTorch DLC
    launch_sft.py      training job launcher (spot, g6e.2xlarge by default)
    Dockerfile.verifier, entrypoint_verifier.sh   x86 verifier image (Godot + Xvfb GL) for Processing jobs
    pipeline_def.py    SageMaker Pipeline: Generate -> Verify -> BuildDataset -> Train -> Evaluate -> gate -> Register
    stage_generate.py, stage_evaluate.py          Processing-step wrappers
  runs/                outputs (gitignored)
```

## Game-side hooks (in `game/`)

- `WorldContext.overrides` + `ctx.layer("sky", SkyLayer)`: worlds ask the
  context for each segment, so `--swap=sky:res://segments/sky/candidates/x.gd`
  replaces one layer without editing the world. Works on the web build too.
- The desktop window (only ever used for captures) is created unfocusable,
  borderless and beyond the screen edge via `.linuxbsd` overrides in
  `project.godot`, so captures on a shared desktop steal neither focus nor
  screen space. A minimised window would stop rendering under GNOME. For a
  box with root, `pipeline/xorg-headless.conf` starts a second GPU X server
  with no monitor (`CAPTURE_DISPLAY=:2`).
- `--capture=<dir> --shots=3,6,9 --script=4:Drag_0_-220,7:Drag_-320_0`:
  native capture. Saves the viewport at those seconds after `world ready`,
  injects the same key/drag script the browser harness uses, and writes
  `stats.json` (fps, draw calls, published palette). On the dev box
  (`DISPLAY=:0`, GB10) an episode is about 12 s at 160 fps instead of the
  minute the web export + Chromium path takes.

## Running it locally

```
pipeline/.venv/bin/python pipeline/briefs.py sky --n 24 --out pipeline/runs/sky1/briefs.jsonl
pipeline/.venv/bin/python pipeline/teacher.py --briefs pipeline/runs/sky1/briefs.jsonl --out pipeline/runs/sky1 --k 2
DISPLAY=:0 pipeline/.venv/bin/python pipeline/verify.py --candidates pipeline/runs/sky1/candidates.jsonl --out pipeline/runs/sky1
pipeline/.venv/bin/python pipeline/teacher.py --revise pipeline/runs/sky1/verified.jsonl --out pipeline/runs/sky1
DISPLAY=:0 pipeline/.venv/bin/python pipeline/verify.py --candidates pipeline/runs/sky1/revisions.jsonl --out pipeline/runs/sky1 --name verified_rev.jsonl
pipeline/.venv/bin/python pipeline/build_sft.py --verified pipeline/runs/sky1/verified.jsonl pipeline/runs/sky1/verified_rev.jsonl --out pipeline/runs/sky1/sft
```

Models (Bedrock inference profiles, `us-west-2`): teacher
`us.anthropic.claude-sonnet-5`, judge and director `us.anthropic.claude-fable-5-1`.
Override with `TEACHER_MODEL`, `JUDGE_MODEL`, `DIRECTOR_MODEL`.

## Training on SageMaker

```
pipeline/.venv/bin/python pipeline/sagemaker/launch_sft.py --data pipeline/runs/sky1/sft --segment sky --dry-run
pipeline/.venv/bin/python pipeline/sagemaker/launch_sft.py --data pipeline/runs/sky1/sft --segment sky
```

The launcher uses the SageMaker Python SDK v2 (`pip install "sagemaker<3"`;
v3 dropped the `PyTorch` estimator) on the `pytorch-training:2.6-gpu-py312`
DLC with `requirements.txt` for TRL and PEFT.
Base model `Qwen/Qwen2.5-Coder-7B-Instruct`, LoRA r=32 on all projections,
6k context, loss on the assistant turn only, merged weights in the model
artifact. The full pipeline (`pipeline_def.py --upsert --start`) needs the
verifier image pushed to ECR (`scene-verifier`), built on an x86 host.

The same `train_sft.py` runs on the dev box (GB10, 121 GB unified memory) with
the local data paths, and `vllm serve <model_dir>` exposes the result to
`loop/specialist.py --backend local:http://127.0.0.1:8000/v1`.

## The loop

```
pipeline/.venv/bin/python pipeline/loop/director.py "a foggy dawn on the street, sun low behind the walker" \
    --out pipeline/runs/loop1 --backend teacher
```

The director writes `plan.json` (per-segment briefs), each specialist writes
its layer, the verifier scores it, evidence becomes the revision brief, up to
three rounds. Accepted layers land in `game/segments/<segment>/generated/`
and `report.json` gives the URL fragment to play the result.

## Verifier scoring

- Gates veto: static (starts with `extends SceneLayer`, has `build()`, no
  forbidden APIs, no `class_name`), runtime (headless boot with the swap, no
  `ERROR`/`SCRIPT ERROR`, reaches `world ready`).
- Checks (sky): sun elevation and azimuth from the published `sun_dir`
  against the brief, palette published, draw calls added <= 40, fps >= 60,
  upper-sky brightness plausible for the time of day.
- Judge: rubric + brief + three frames -> six attribute scores with
  evidence, `overall`, `pass`, `revision_notes`.
- `score = 0.4 * checks + 0.6 * judge/10`; `pass = judge.pass and checks >= 0.6`.
