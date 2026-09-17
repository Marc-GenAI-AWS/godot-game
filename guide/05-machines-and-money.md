# 5. Machines, accounts and money

## The two machines

**navani** — the development box and where everything in this repo runs.
NVIDIA GB10, 121 GB unified memory, aarch64, Ubuntu. It has the repo, both
virtualenvs, the Godot binary (`~/opt/godot/Godot_v4.7.2-stable_linux.arm64`,
arm64, with web export templates), the trained models under `~/models/`, and
`ollama` as a **system** service (`systemctl stop ollama`, not `--user` — a
`--user` command is a silent no-op here).

Native GPU capture needs the desktop session:
`DISPLAY=:0 XAUTHORITY=/run/user/1000/gdm/Xauthority`. Godot renders OpenGL on
the GB10 at ~140 fps. In capture mode the window is borderless, unfocused and
parked beyond the screen edge — minimising it would stop rendering under
GNOME.

**amalia** — the GPU host. RTX PRO 6000 Max-Q, reached over Tailscale
(`ssh amalia`). Its only job is the shared **Qwen3.8-27B on vLLM**, port 8001,
model id `qwen38-27b`, used by this project and by Marc's ThreeJS project. Its
address is `VLLM_HOST` in `pipeline/aws.env`. Standing rule from Marc:
**nothing else gets loaded onto that card.**

Two things to know about it:

- The server needs `chat_template_kwargs: {"enable_thinking": false}` in every
  request or the model narrates its reasoning into your JSON.
- Its serve script must export `CUDA_HOME=/usr/local/cuda-13.0`; an older
  `nvcc` 12.0 on `PATH` breaks vLLM's DeepGEMM at startup.

**Shared storage** — a 3.6 TB LVM volume on amalia (`/srv/shared`) exported
over NFS4 and automounted on navani at `/mnt/shared`, ~282 MB/s. Big model
weights live there (`/srv/shared/models/`).

**As of 2026-09-16:** nothing is generating on either machine. amalia's vLLM
port is closed (server not running) and navani has no pipeline units active.
SSH to amalia now goes through Tailscale SSH and asks for a browser
re-authentication, so expect to run `tailscale up` or follow the auth link
before your first shell there.

## AWS

Two regions are in play: `us-west-2` is the default, and `us-east-2` is where
most training actually ran, because capacity in us-west-2 kept running out.

**The account id, the role ARN and the bucket names are not in this repository
— it is public.** They live in `pipeline/aws.env`, which is gitignored;
`pipeline/aws.env.example` documents every field. Both the Python entry points
(through `common.load_env()`) and the shell scripts read it, and anything you
export yourself wins over the file. A script that needs a value you have not
set stops and tells you which one and where to put it, rather than falling back
to somebody else's account.

```bash
cp pipeline/aws.env.example pipeline/aws.env    # then fill it in
```

| What | Where |
|---|---|
| SageMaker role | `SAGEMAKER_ROLE` — needs S3 access to the buckets, and Bedrock for `pipeline_def.py` |
| Buckets | `SAGEMAKER_BUCKET` (us-west-2) and `SAGEMAKER_BUCKET_US_EAST_2`, prefix `scene-studio/` |
| Training artifacts | `s3://<bucket>/scene-studio/<segment>/models/<job>/output/model.tar.gz` |
| Judge + director call logs | synced hourly from `pipeline/runs/_calls` by the `scene-calllog-archive` user unit |

Bedrock models are reached by **inference-profile id**, not bare model id
(`us.anthropic.claude-sonnet-5` teacher and judge,
`us.anthropic.claude-opus-5` for the vegetation/props/composite judge,
`us.anthropic.claude-fable-5-1` director). Bare ids fail with "on-demand
throughput isn't supported", and Claude 5 models reject a `temperature`
parameter.

Every knob is an environment variable, settable in `aws.env` or inline:
`AWS_REGION`, `SAGEMAKER_ROLE`, `SAGEMAKER_BUCKET`,
`SAGEMAKER_BUCKET_US_EAST_2`, `AWS_ACCOUNT`, `VLLM_HOST`, `TEACHER_MODEL`,
`JUDGE_MODEL`, `DIRECTOR_MODEL`, `GODOT_BIN`, `GODOT_MEM_GB`, `MODELS_DIR`.

## What things cost

Real numbers from this project, not estimates:

| Thing | Cost |
|---|---|
| One judge call (Sonnet + frames) | ~$0.026 |
| One teacher candidate or revision | ~$0.064 |
| A full data run (~144 briefs x 2 + revisions) | $30-50 |
| One LoRA training job (3B or 7B, g6e) | ~$1-2, 12-46 minutes |
| A scene from the director loop | judge calls only — the models are local |
| Total Bedrock spend to date | ~$335 |

The expensive surprise was re-judging: on one day the judge cost $221 against
the teacher's $80, because failed experiments were re-judged repeatedly. Before
any bulk re-judge, check whether `verify.py --rescore --rejudge-saved none` can
answer the question from saved verdicts for free.

Training is cheap; generation and judging are not. Nothing spends money unless
you run it, but an orchestrator script can spend $50 unattended.

## Artifacts that are not in git

This matters most for a handover — the repo alone is not the project.

| What | Where | Size | If it were lost |
|---|---|---|---|
| Trained specialists + director | `~/models/<job>/` on navani, and S3 | ~50 GB | Re-download from S3; adapters are also in the job output |
| Datasets, captures, verdicts, logs | `pipeline/runs/` (gitignored) | 39 GB | The models survive, the evidence does not — re-running a data run costs $30-50 |
| Human anchor labels | `pipeline/anchors/*.jsonl` | tiny | **In git.** These are irreplaceable — they are a person's judgement |
| Model-written layers | `game/segments/*/generated/` | 500 KB | **In git** since 2026-09-16 |
| Verifier candidates | `game/segments/*/candidates/` | ~3,600 files | Disposable by design |

The current best model per segment:

| Segment | Job / directory | Size |
|---|---|---|
| sky | `scene-sky-sft-20260916-1021` | 3B |
| ground | `scene-ground-sft-20260915-1449` | 3B |
| vegetation | `scene-vegetation-sft-20260914-2028` | 3B |
| props | `scene-props-sft-20260915-1443` | 7B |
| water | `scene-water-sft-20260915-0959` | 3B |
| director | `qwen3-8b` + `director-8b-adapter` | 8B + LoRA |

## Access a new person needs

- The `Marc-GenAI-AWS` GitHub org/account, for the repo and the Pages site.
- The AWS account, with Bedrock model access in us-east-2/us-west-2 and
  SageMaker training permissions — or their own account, which is only a
  matter of filling in `pipeline/aws.env`.
- SSH to navani and amalia (Tailscale).
- Nothing else. There are no API keys in the repo and no secrets in the
  scripts; everything authenticates through the AWS CLI profile and `gh`, and
  every account-specific value is in the untracked `pipeline/aws.env`.

## Licences

Characters are Quaternius **Universal Base Characters** and **Universal
Animation Library**, both CC0, retargeted at import. Everything else in the
game is procedural — generated from code. The base models are Qwen2.5-Coder
and Qwen3 (Apache-2.0); check the licence terms before shipping a fine-tune of
them in a product. The reference clips in `examples/` are gitignored and were
never redistributed — keep it that way.
