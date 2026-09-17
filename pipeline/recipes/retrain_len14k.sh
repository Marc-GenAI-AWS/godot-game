#!/bin/bash
# Retrain a segment's specialist on an existing dataset at max-len 14336 (Liger) and evaluate it on the
# same held-out briefs as the 6144-token model, printing beach/street splits for both.
#   runs/retrain_len14k.sh <segment> <data run> <base model> <old eval name> [units whose evals must finish first]
#   e.g. runs/retrain_len14k.sh ground ground234 Qwen/Qwen2.5-Coder-3B-Instruct eval-ground234-3b scene-props5-street scene-props-len14k
# Sep 15: at 6144 tokens 207/239 ground234 examples lost the end of their answer (contract 5.0k tokens).
set -uo pipefail
P=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)   # pipeline/
cd $P
SEG=$1; RUN=$2; MODEL=$3; OLD=$4; shift 4; AFTER="$*"
# account-specific values (bucket, role, LAN hosts) live in pipeline/aws.env - see aws.env.example
set -a; [ -f "$P/aws.env" ] && . "$P/aws.env"; set +a
export DISPLAY=:0 XAUTHORITY=/run/user/1000/gdm/Xauthority AWS_REGION=us-east-2 SAGEMAKER_BUCKET=${SAGEMAKER_BUCKET_US_EAST_2:?set it in pipeline/aws.env}
tag=$(echo $MODEL | sed 's/.*Coder-//; s/-Instruct//' | tr 'A-Z.' 'a-zp')
EVAL=eval-$RUN-$tag-len14k
B=s3://$SAGEMAKER_BUCKET/scene-studio/$SEG/models
job=""
for try in $(seq 1 60); do   # one training instance per size in the region: wait for a free slot
  for inst in ml.g6e.xlarge ml.g6e.2xlarge; do
    out=$(.venv/bin/python sagemaker/launch_sft.py --data runs/$RUN/sft --segment $SEG --spot 0 --instance $inst \
          --model $MODEL --max-len 14336 --liger 1 --max-hours 6 2>&1 | grep '^launched')
    job=$(echo "$out" | sed 's/launched \([^;]*\);.*/\1/')
    [ -n "$job" ] && break
  done
  [ -n "$job" ] && break
  echo "   no free training slot (try $try); waiting"; sleep 90
done
[ -z "$job" ] && { echo "== could not launch $SEG $tag at 14336"; exit 1; }
echo "== $(date +%T) launched $job ($SEG $tag, max-len 14336, liger)"
# wait on the job status, not on model.tar.gz: SageMaker uploads a 236-byte model.tar.gz for failed jobs too
while true; do
  st=$(aws sagemaker describe-training-job --training-job-name $job --region us-east-2 --query TrainingJobStatus --output text 2>/dev/null)
  [ "$st" = "Completed" ] && break
  if [ "$st" = "Failed" ] || [ "$st" = "Stopped" ]; then
    echo "== $job $st: $(aws sagemaker describe-training-job --training-job-name $job --region us-east-2 --query FailureReason --output text | cut -c1-300)"; exit 1
  fi
  sleep 60
done
echo "== $(date +%T) $job completed: $(aws logs tail /aws/sagemaker/TrainingJobs --log-stream-name-prefix $job --region us-east-2 --since 8h --format short 2>/dev/null | tr '\r' '\n' | grep -E "^.{20}eval \{" | tail -1 | cut -c21-160)"
# one local eval at a time (GPU + Godot captures): wait for the other runs' evals
for u in $AFTER; do
  while systemctl --user is-active -q $u; do sleep 60; done
done
echo "== $(date +%T) evaluating $job as $EVAL"
./eval_specialist.sh "$B/$job/output/model.tar.gz" $EVAL runs/$RUN/sft/heldout_briefs.jsonl $SEG > runs/$EVAL.log 2>&1 || echo "== $EVAL FAILED"
grep -A 9 '"heldout_briefs"' runs/$EVAL.log | head -10
python3 - $OLD $EVAL <<'EOF'
import json, sys
for name in sys.argv[1:]:
    try:
        first = [json.loads(l) for l in open(f"runs/{name}/verified.jsonl")]
        rev = {json.loads(l)["candidate"][:-1]: json.loads(l) for l in open(f"runs/{name}/verified_rev.jsonl")}
        rep = json.load(open(f"runs/{name}/eval.json"))
    except FileNotFoundError:
        continue
    out = []
    for w in ("beach", "street"):
        rows = [r for r in first if r["brief"]["world"] == w]
        after = sum(1 for r in rows if r["pass"] or rev.get(r["candidate"], {}).get("pass"))
        out.append(f"{w} {sum(r['pass'] for r in rows)}/{len(rows)} one-shot, {after}/{len(rows)} after revision")
    print(f"== {name}: one-shot {rep['one_shot_pass_rate']}, after revision {rep['after_one_revision_pass_rate']}, "
          f"teacher {rep['teacher_one_shot_pass_rate_same_briefs']}; " + "; ".join(out))
EOF
echo "== $(date +%T) $SEG $tag 14336-token run done"
