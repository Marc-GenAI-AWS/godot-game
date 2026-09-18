# 6. Where it stands

Written 2026-09-16, at handover.

## What works

Every specialist now beats the model that taught it. One-shot means the first
layer it wrote; "revised" means after one self-revision from the verifier's
evidence. All measured on held-out briefs the model never trained on, judged by
the same verifier at the same bar as the teacher.

| Segment | Model | One-shot | Revised | Teacher | Held out |
|---|---|---|---|---|---|
| sky | 3B | 80% | 90% | 73% | 30 |
| vegetation | 3B | 72% | 83% | 57% | 18 |
| props | 7B | 71% | 95% | 52% | 21 |
| water | 3B | 46% | 63% | 42% | 24 |
| ground | 3B | 32% | 68% | 34% | 25 |
| director | 8B | 47/47 briefs, 188/188 fields translated exactly | | 80% | 47 |

The eight published scenes were planned and written entirely by local
fine-tuned models, with Claude only judging: vegetation was accepted in 8/8
scenes, sky 7/8, ground 6/8, props 6/8. Four of the eight had all four layers
model-written; six were marked publishable by the composite judge.

That is the headline: **a 3B model on one workstation writes better scene code
than the frontier model that generated its training data** — for one narrow,
verifiable job.

## Things that turned out to be the judge

Three separate times, a "model problem" was a measurement problem. Worth
knowing before you chase a fourth:

- **Sky's famous 77%** came from a lenient judge that was later replaced.
  Re-judging the same saved frames with the current judge turned it into 13%.
  The model had not changed at all.
- **Sky's "big improvement" after retraining** was mostly the pass bar moving
  from 7 to 6. Re-scoring the *old* models at the new bar showed 20/30 and
  21/30 against the new model's 24/30 — real, but a third of the headline.
- **Vegetation collapsed from 20/40 to 1/40** overnight when the default judge
  changed from one Claude model to another. Same frames, same layers.

Hence the anchor sets, the explicit `pass_bar`, and the rule that re-scoring
the old model at the new bar comes before any claim.

## Known problems

**Ground is the weak segment.** 32% one-shot, and beach ground is 3/8 even
after revision. Its failures are mostly the judge scoring 6 on colour and
surface — and ground is the only trained segment with **no anchor set**, so
nobody knows whether 6 is really a failure. Building one (24 layers, a person
labelling pass/fail for an hour, free) is the highest-value hour available.

**The local judge is not yet a replacement.** A 27B vision model at the same
prompts agrees with the human labels about as often as Claude does in
aggregate, but it is lenient on sky, harsh on water, and ranks layers the same
way as Claude only 64% of the time. A calibrated prompt
(`local_judge_prompt_test.py`) is written and partly tested. Getting this to
work would take the per-scene cost to zero.

**vLLM is broken on navani** — `vllm 0.17.0` against `torch 2.14` fails with
`_C.abi3.so: undefined symbol`. Local generation uses transformers instead,
which is why evaluating 30 briefs takes ~17 minutes instead of ~2. Fixing the
environment would speed every eval up by an order of magnitude.

**Smaller things:** `pipeline/.venv-train` has transformers 4.57 while
`sagemaker/requirements_director.txt` wants 5.x (the director's SageMaker job
ships its own requirements, so this only matters locally). `gdcheck.py` checks
`Class.CONST` but only partially catches `local.CONST`. There is a leftover
`boulder/` directory at the repo root from before the rename. Water's data runs
yield diminishing examples per dollar.

## Open threads, in the order I would take them

1. **A ground anchor set.** Free, one hour of labelling, and it either raises
   ground's real score or proves the model is genuinely weak. Everything else
   about ground is guesswork until then.
2. **Retest the props 3B at `--max-len 14336`.** The 7B beat the teacher, but
   the 3B was only ever trained on truncated data. If the 3B closes the gap,
   inference gets three times cheaper. One training job, ~$2.
3. **Extend `brief_gen.py` beyond characters.** The hand-written samplers have
   a hard combinatorial ceiling (street ground is 324 combinations), so a
   72-brief run mostly repeats what the specialist has already seen. A model
   writing briefs, validated against what the game can actually build, is how
   the data stops repeating itself.
4. **A characters/crowd specialist.** The most visible segment with no
   specialist, and `brief_gen.py` already generates and validates its briefs.
   Needs a contract and a rubric first.
5. **Finish the local judge.** See above.
6. **A third world.** The framework carries most of the cost already, and it
   would show whether the specialists generalise beyond beach and street.

**Paused by Marc, not abandoned:** a "new generation" entry at the top of each
in-game menu — you type a concept, it is generated and appears in the menu.
The design settled was: sky first (fastest segment, no assets needed), outfits
via ComfyUI, hair meshes not feasible, and LAN-only — it cannot run on a static
Pages site.

## How to tell you have not broken anything

There is no CI, so there is one command:

```bash
tools/selftest.sh            # everything, about a minute
tools/selftest.sh --quick    # skips the two simulations; saves about ten seconds
```

It runs every check below, fails loudly, and exits non-zero. Two things about how it judges,
both of which exist because of bugs that shipped:

* **a single `SCRIPT ERROR` fails the run, whatever else the check printed.** A dropped
  reference in a per-frame loop produced 180 errors a second and froze the browser tab, while
  the test it ran under still reported DONE.
* **the harness proves it can fail.** The last check is one that cannot pass, and the run fails
  if that check passes. A green suite that is green because nothing is being asserted is worse
  than no suite.

Reintroducing the freeze bug makes it report `FAIL street menu - 1172 script errors` and exit 1,
which is the only evidence worth having that a test works.

The individual checks, if you want to run one:

```bash
# the game boots, builds every layer, and its world assertions pass
godot --headless --path game --quit-after 30 | grep contacts

# the right-click menu still swaps layers, dresses the player and resets
godot --path game -- --world=beach --menutest        # prints MENUTEST ... DONE

# the static gate agrees with itself (0 false positives on passing layers)
cd pipeline && .venv/bin/python -c "
from gdcheck import check
from pathlib import Path
bad = [p for p in Path('../game/segments').glob('*/generated/*.gd') if check(p.read_text())]
print('flagged:', [p.name for p in bad])"
```

A verifier run on a handful of candidates is the real end-to-end test, and it
costs a few judge calls.

## The one thing to keep hold of

The verifier is the asset. The models are cheap to retrain and will be
obsolete within a year; the contracts, the rubrics, the anchor labels and the
checks are what make a model's output falsifiable, and they took the longest to
get right. If you change nothing else, keep the loop honest: every claim about
a model should come with the held-out briefs it was measured on and the bar it
was measured at.
