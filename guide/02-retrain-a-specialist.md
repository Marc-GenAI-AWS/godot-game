# 2. Retraining a specialist

One specialist writes one layer. Today there are five (sky, ground, water,
vegetation, props) plus a director. This page is the loop that makes them
better.

Everything runs from `pipeline/`. Two virtualenvs: `.venv` (boto3, sagemaker,
pillow — the pipeline itself) and `.venv-train` (torch, transformers, peft —
local generation and evaluation).

## The loop

```
briefs  →  teacher writes candidates  →  verifier  →  dataset  →  SageMaker LoRA  →  eval
              (Claude on Bedrock)       (renders +                                     |
                                         judges)                                       |
                                              ↑                                        |
                                              └──────── the same verifier grades ──────┘
```

The verifier is the whole trick: it filters the training data *and* decides
whether the trained model is any good, so the bar is the same at both ends.

### One command per stage

```bash
cd pipeline

# 1. briefs: structured, spread evenly over time-of-day x weather
.venv/bin/python briefs.py sky --n 144 --seed 22 --out runs/sky3/briefs.jsonl

# 2. teacher: k candidate layers per brief (Claude Sonnet on Bedrock — this costs money)
.venv/bin/python teacher.py --briefs runs/sky3/briefs.jsonl --out runs/sky3 --k 2 --workers 6

# 3. verify: static gate → runtime gate → checks → capture → judge
.venv/bin/python verify.py --candidates runs/sky3/candidates.jsonl --out runs/sky3 --workers 3

# 4. give every failure one revision, with the verifier's evidence as the prompt
.venv/bin/python teacher.py --revise runs/sky3/verified.jsonl --out runs/sky3 --workers 6
.venv/bin/python verify.py --candidates runs/sky3/revisions.jsonl --out runs/sky3 \
    --name verified_rev.jsonl --workers 3

# 5. dataset (pin the held-out briefs to an earlier build so evals stay comparable)
.venv/bin/python build_sft.py --verified runs/sky3/verified.jsonl runs/sky3/verified_rev.jsonl \
    --out runs/sky123/sft --heldout runs/sky12/sft/heldout_briefs.jsonl
```

Stages 1-5 for one segment are `./run_segment.sh <segment> <run> <n briefs> <k>`.
Then:

```bash
# 6. train on SageMaker and evaluate when the artifact lands
./train_eval_segment.sh sky sky123           # MODELS="..." for a bake-off; MIN_EXAMPLES guards it

# 6b. or train by hand
.venv/bin/python sagemaker/launch_sft.py --data runs/sky123/sft --segment sky \
    --model Qwen/Qwen2.5-Coder-3B-Instruct --max-len 14336 --liger 1 --instance ml.g6e.2xlarge

# 7. evaluate any model on the held-out briefs, against the teacher on the same briefs
./eval_specialist.sh /home/marc/models/<job> eval-sky123-3b runs/sky12/sft/heldout_briefs.jsonl sky
```

`pipeline/recipes/` holds the scripts that actually produced the current
models — `sky3.sh` is a complete fresh data run plus retrain, end to end, and
is the best template to copy.

## What the verifier does

Five stages, cheapest first, in `pipeline/verify.py`:

1. **Static gate** — the code parses, and `gdcheck.py` catches invented engine
   constants, wrong-arity built-in constructors, C functions used as GDScript
   (`cosf` instead of `cos`), and uppercase members invented on a context
   local. Zero false positives across 1,762 passing layers.
2. **Runtime gate** — headless Godot loads the layer in its world. Every Godot
   runs under `prlimit --data` (`GODOT_MEM_GB`, default 8): one runaway
   generated layer grew to 91 GB and the kernel OOM-killed the orchestrator.
3. **Checks** — deterministic numbers from `stats.json`: palette, draw-call
   budget, fps floor, obstacle counts. Scored; the bar is `cscore >= 0.6`.
4. **Capture** — native GPU capture on `DISPLAY=:0`, three frames at the
   segment's shot times, driven by a scripted walk so the frames are
   repeatable.
5. **Judge** — a Claude vision model scores the frames against the rubric and
   the brief, 0-10 per attribute plus an overall, with evidence per attribute.
   Some segments also get reference frames from the hand-built layer.

A layer passes when `judge_pass(segment, verdict) and cscore >= 0.6`.

## Calibrating the judge

**This is the part to be careful about.** Pass rates move when the judge moves.
The history is in [page 6](06-state-of-play.md#things-that-turned-out-to-be-the-judge),
but the rules that came out of it:

- **Anchor sets are ground truth.** `pipeline/anchors/anchor{1,2,3}.jsonl` are
  76 layers a human labelled pass/fail. When a judge or a bar changes, score it
  against these before believing anything.
- **A bar is `SEGMENTS[seg]["pass_bar"] = {"overall": N, "min_attribute": M}`.**
  Sky and water are 6/4, from anchor3 and anchor2 respectively. The others use
  the judge's own pass flag. Ground has no anchor set — that is the most
  valuable missing hour of work in the project.
- **Re-scoring is free.** Verdicts are saved, so
  `verify.py --rescore --rejudge-saved none` re-applies a new bar to old runs
  without a single API call. Always re-score the *old* model at the *new* bar
  before claiming an improvement. A sky model once "improved" from 13% to 77%
  purely because the judge had changed underneath it.

## The truncation trap

Every SFT job ran at `--max-len 6144` for weeks. The contract alone is ~5,000
tokens for props, so the answer was silently cut off: 528 of 529 props examples
and 207 of 239 ground examples were truncated, many with *zero* answer tokens
left (which is what `eval_loss: nan` meant). Fixing it took props from 38% to
71% one-shot with the same data and the same model size.

The default is now 14336. If you change the contract or add examples, check
before you spend:

```bash
.venv/bin/python - <<'EOF'
import json
from transformers import AutoTokenizer
tok = AutoTokenizer.from_pretrained("Qwen/Qwen2.5-Coder-7B-Instruct")
n = [len(tok.apply_chat_template(json.loads(l)["messages"], tokenize=True))
     for l in open("runs/<run>/sft/train.jsonl")]
print("max", max(n), "over 14336:", sum(1 for x in n if x > 14336), "of", len(n))
EOF
```

Long sequences OOM on a 44 GB L40S without `--liger 1` (fused cross-entropy;
the logits allocation alone was 6.7 GB) plus
`PYTORCH_CUDA_ALLOC_CONF=expandable_segments`. Both are defaults now.
`--max-steps N` runs a cheap smoke job first — worth it before a long one.

## Rules of thumb earned the expensive way

- **Below ~100 real examples an adapter cannot approach its teacher.**
  `train_eval_segment.sh` refuses (`MIN_EXAMPLES`); synthetic repair examples
  do not count toward it.
- **Repair examples help more than model size.** `make_repair_pairs.py` takes a
  passing layer, injects a realistic error, records the verifier's real
  rejection and the original as the fix. Targeted repairs took props from 9.5%
  to 28.6%; going 3B → 7B added another 10 points.
- **Small models do not learn to fix gate errors from prose evidence.** Better
  error hints changed 1 of 6 revisions. Training examples of the repair and
  static catches in `gdcheck.py` are the levers.
- **One revision is worth a lot.** Every specialist gains 15-35 points from a
  single self-revision with the verifier's evidence. That is why the director
  loop revises.
- **Keep the held-out briefs pinned** with `build_sft.py --heldout`, or you are
  comparing models on different exams.
- **A SageMaker job that FAILS still uploads a 236-byte `model.tar.gz`.** Wait
  on `TrainingJobStatus`, never on the artifact appearing.
- **Capacity, not money, is usually the blocker.** The account has one large
  training instance per size per region; the scripts retry across
  `ml.g6e.xlarge` / `ml.g6e.2xlarge` and across us-west-2 / us-east-2.

## Trying a local teacher instead of Claude

`teacher.py --backend local:http://<host>:8001/v1` points generation at a local
vLLM model, and `--notes` appends `contract/teacher_notes/<segment>.md` — extra
coaching written from that model's own failures, added only when generating,
never to what the specialists train on. Measured on ground: the local model's
candidates survive at 25% vs Claude's 44%, so it is roughly half the cost and
twice the wall-clock. 14 of its 21 gate failures were a single GDScript scoping
mistake, which is what the notes file addresses.
