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
  loop/director.py     scene brief -> per-segment briefs -> specialists -> verify -> revise -> composite -> install
  rubrics/composite.md the whole-scene rubric (coherence, brief match, integration, artifacts, per-segment blame)
  calllog.py           full judge / director call records + content-addressed frames (training data for local models)
  backfill_calllog.py  records judgements made before call logging (verdict + frames only)
  archive_calllog.sh   syncs runs/_calls and runs/_frames to S3
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

First: `cp pipeline/aws.env.example pipeline/aws.env` and fill it in. That file
is gitignored and holds every account-specific value (role ARN, buckets,
account id, the vLLM host) — this repository is public, so none of them are in
the source. `common.load_env()` reads it on import and the shell scripts source
it; anything already exported wins.

```
pipeline/.venv/bin/python pipeline/briefs.py sky --n 24 --out pipeline/runs/sky1/briefs.jsonl
pipeline/.venv/bin/python pipeline/teacher.py --briefs pipeline/runs/sky1/briefs.jsonl --out pipeline/runs/sky1 --k 2
DISPLAY=:0 pipeline/.venv/bin/python pipeline/verify.py --candidates pipeline/runs/sky1/candidates.jsonl --out pipeline/runs/sky1
pipeline/.venv/bin/python pipeline/teacher.py --revise pipeline/runs/sky1/verified.jsonl --out pipeline/runs/sky1
DISPLAY=:0 pipeline/.venv/bin/python pipeline/verify.py --candidates pipeline/runs/sky1/revisions.jsonl --out pipeline/runs/sky1 --name verified_rev.jsonl
pipeline/.venv/bin/python pipeline/build_sft.py --verified pipeline/runs/sky1/verified.jsonl pipeline/runs/sky1/verified_rev.jsonl --out pipeline/runs/sky1/sft
```

Models (Bedrock inference profiles, `us-west-2`): teacher and judge
`us.anthropic.claude-sonnet-5`, director `us.anthropic.claude-fable-5-1`.
Override with `TEACHER_MODEL`, `JUDGE_MODEL`, `DIRECTOR_MODEL`.

## Call logs (for local judge and director models later)

Claude stays the judge and director for now, but every call is recorded in
full so both roles can later be distilled into local models:

- `runs/_calls/judge.jsonl`: one line per judge call with the rubric
  (system prompt), the prompt blocks (brief text, labels, reference and
  candidate images by SHA-256), the raw reply and any JSON-repair reply, the
  parsed verdict, usage, and the run / candidate it belongs to. Rows of type
  `backfill` predate full logging and carry only the verdict and frames.
- `runs/_calls/director.jsonl`: a `plan` line per director call (system
  prompt, scene brief, raw reply) and an `outcome` line per loop run (the
  plan, each round's pass / score / judge overall, accepted segments).
- `runs/_frames/<ab>/<sha256>.png`: every image a judge saw, stored once.
  Captures are deleted when a run is re-verified and reference frames are a
  shared cache, so the log keeps its own copies.

Logging never breaks a run (failures print a warning). After a data run:

```
pipeline/.venv/bin/python pipeline/backfill_calllog.py   # only needed once for older runs; safe to re-run
pipeline/archive_calllog.sh                              # sync both to s3://$SAGEMAKER_BUCKET/call-logs/
```

## Composite verifier (whole scenes)

Each layer passes the verifier alone, inside the otherwise shipped scene. The
composite verifier (`verify.verify_composite`) judges the assembled scene:
every accepted layer at once, captured with the vegetation views and the sky's
tilted-up views, against the shipped scene under the same views, with the
whole-scene rubric (Opus 5). It scores coherence (one time of day, one light,
one weather), brief match, integration and artifacts, and gives every segment
a score, a problem and a fix.

```
PYTHONPATH=pipeline pipeline/.venv-train/bin/python pipeline/loop/director.py "an overcast morning on a palm-lined street" \
    --out pipeline/runs/scene1 --segments sky,ground,vegetation \
    --backend sky=hf:~/models/<sky job>,ground=hf:~/models/<ground job>,vegetation=hf:~/models/<veg job> \
    --composite --composite-rounds 1
```

If the composite fails, each blamed segment with a specialist revises from its
accepted layer (or its last draft) with the composite's problem and fix as
evidence, through the normal per-layer check; the scene is judged again, up to
`--composite-rounds` times. `report.json` records every composite verdict and
sets `publishable` only when the last one passed. The scene-level check is the
60 fps floor; scene draw-call totals are reported but not scored, because they
follow what is on screen at the capture moment (the same shipped street counted
81 and 681 under the two recipes). Each layer's own check keeps its budget.

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

## Model size

One size for every segment: **Qwen2.5-Coder-3B-Instruct** with a LoRA
adapter per segment (decided 2026-09-13 after the sky bake-off, where 1.5B
and 3B tied at 77% one-shot and 7B trailed at 60%). 3B is kept over 1.5B for
headroom on the segments whose datasets are still small. `train_eval_segment.sh`
trains 3B only; set `MODELS="Qwen/Qwen2.5-Coder-1.5B-Instruct Qwen/Qwen2.5-Coder-3B-Instruct"`
to run a bake-off again.

## Evaluating a specialist

```
pipeline/eval_specialist.sh s3://.../model.tar.gz eval-sky-sft1            # or a local model dir
```

Downloads and extracts the merged model, generates one layer per held-out
brief with transformers on the local GPU (`loop/specialist.py --backend
hf:<dir>`, batched), verifies them, and prints the specialist's pass rate and
judge mean next to the teacher's on the same briefs (`runs/<run>/eval.json`).

Lessons from the first job (2026-09-12): the L40S family (`g6e`) had no
capacity in us-west-2 for 40 minutes on spot, on-demand or the smaller size,
and `g5.12xlarge` was pending too; the same job started within two minutes in
us-east-2 (`AWS_REGION=us-east-2 SAGEMAKER_BUCKET=<us-east-2 bucket>`). The
epoch-end evaluation must use batch size 1: eight 6k-token logit tensors are
one 16 GB allocation. Training-instance quotas are per region: us-east-2 has
1 x `g6e.xlarge` and 1 x `g6e.2xlarge` for training, so at most two adapters
train at once there. Three epochs over 140 examples took 12.5 minutes on one
L40S, about $0.75 billable.

### Results so far (sky)

| Adapter | Data | Held-out briefs | One-shot pass | After one self-revision | Teacher one-shot, same briefs |
|---|---|---|---|---|---|
| 7B LoRA, contract v1 data | 140 examples | 18 | 39% (6 gate fails) | 78% | 61% |
| 7B LoRA, contract v1.1 data | 293 examples | 30 | 60% (0 gate fails, judge 6.83 vs 6.64) | 77% | 60% |
| 3B LoRA, contract v1.1 data | 293 examples | 30 | 77% (0 gate fails, judge 6.90) | 80% | 60% |
| 1.5B LoRA, contract v1.1 data | 293 examples | 30 | 77% (0 gate fails, judge 6.93) | 80% | 60% |

Vegetation (63 examples, 50 train):

| Adapter | Held-out briefs | One-shot pass | After one self-revision | Judge mean | Teacher one-shot, same briefs |
|---|---|---|---|---|---|
| 1.5B | 9 | 0% (4 gate fails) | 0% | 5.2 | 56% |
| 3B | 9 | 0% (2 gate fails) | 11% | 5.57 | 56% (judge 6.35) |

Fifty examples is not enough: both adapters compile most of the time and place
plants correctly (checks 0.8 to 1.0) but the judge scores them 4 to 6, below
the teacher's 6.35. Sky needed about 250 examples to reach parity.

Props (73 examples, 60 train): the 3B adapter passes 0 of 9 held-out briefs
(judge mean 4.2 vs the teacher's 6.85; four beach candidates emit an invented
`endfunc` keyword). Same conclusion: below about 100 examples an adapter is
not worth evaluating, so `train_eval_segment.sh` now refuses datasets under
`MIN_EXAMPLES` (default 100). The unit of progress per segment is verified
examples, and the runs that produce them accumulate.

The gap between the specialist and the teacher one-shot is entirely code that
fails to load (duplicate `var` declarations, a hallucinated `aerial_perspective`
property); judge quality on the candidates that ran was at parity (6.67 vs
6.69). With the verifier's evidence fed back once, the specialist beats the
teacher's one-shot rate, which is how the loop uses it. The second adapter,
trained on data written under the same contract it is prompted with, reaches
teacher parity one-shot with no gate failures at all, and the 3B and 1.5B
adapters on the same data do better still while generating in half and a
third of the time. Thirty briefs is a small sample (about +/-9 points), and
the three adapters pass overlapping but not identical briefs (15 pass under
all three, 27 under at least one), but the ordering 1.5B ~ 3B >= 7B >= teacher
one-shot is the result the design predicted for an easy segment: sky
saturates early and the smallest model clears the bar. Where the adapters
still fail is dusk (1 to 4 of 6) and noon "broken clouds" briefs, the same
cloud-cover weakness the teacher has.

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
