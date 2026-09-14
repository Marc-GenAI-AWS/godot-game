#!/bin/bash
# Train the segment's 3B adapter on SageMaker (us-east-2) and evaluate it on
# the held-out briefs when the artifact lands (MODELS=... for a bake-off).
#   pipeline/train_eval_segment.sh <segment> <data run name>   e.g. vegetation veg1
set -uo pipefail
cd "$(dirname "$0")"
SEG=$1; RUN=$2
N=$(wc -l < runs/$RUN/sft/train.jsonl 2>/dev/null || echo 0)
MIN=${MIN_EXAMPLES:-100}   # below this an adapter cannot approach the teacher (sky needed ~250); don't spend on it
if [ "$N" -lt "$MIN" ]; then echo "== $SEG: only $N training examples in runs/$RUN (minimum $MIN); not training"; exit 0; fi
export AWS_REGION=us-east-2 SAGEMAKER_BUCKET=amazon-sagemaker-605134472325-us-east-2-6df5g199r0fy5l
B=s3://$SAGEMAKER_BUCKET/scene-studio/$SEG/models
declare -A JOBS
# One specialist size for every segment (decision 2026-09-13): 3B. Override with MODELS="a b".
for m in ${MODELS:-Qwen/Qwen2.5-Coder-3B-Instruct}; do
  tag=$(echo $m | sed 's/.*Coder-//; s/-Instruct//' | tr 'A-Z.' 'a-zp')
  echo "== $(date +%T) launching $SEG $tag"
  job=""
  for try in $(seq 1 40); do   # the region allows one training instance per size: wait for a slot
    for inst in ml.g6e.xlarge ml.g6e.2xlarge; do
      out=$(.venv/bin/python sagemaker/launch_sft.py --data runs/$RUN/sft --segment $SEG --spot 0 --instance $inst --model $m 2>&1 | grep '^launched')
      job=$(echo "$out" | sed 's/launched \([^;]*\);.*/\1/')
      [ -n "$job" ] && break
    done
    [ -n "$job" ] && break
    echo "   no free training slot (try $try); waiting"; sleep 90
  done
  if [ -z "$job" ]; then echo "== could not launch $SEG $tag"; continue; fi
  echo "   $job"
  JOBS[$tag]=$job
  sleep 65
done
for tag in "${!JOBS[@]}"; do
  job=${JOBS[$tag]}
  echo "== $(date +%T) waiting for $job"
  until aws s3 ls "$B/$job/output/model.tar.gz" >/dev/null 2>&1; do
    st=$(aws sagemaker describe-training-job --training-job-name $job --region us-east-2 --query TrainingJobStatus --output text 2>/dev/null)
    if [ "$st" = "Failed" ] || [ "$st" = "Stopped" ]; then echo "== $job $st"; aws sagemaker describe-training-job --training-job-name $job --region us-east-2 --query FailureReason --output text | cut -c1-300; continue 2; fi
    sleep 60
  done
  echo "== $(date +%T) evaluating $job as eval-$SEG-$tag"
  ./eval_specialist.sh "$B/$job/output/model.tar.gz" "eval-$SEG-$tag" runs/$RUN/sft/heldout_briefs.jsonl $SEG > runs/eval-$SEG-$tag.log 2>&1 || echo "== eval-$SEG-$tag FAILED"
  grep -A 9 '"heldout_briefs"' runs/eval-$SEG-$tag.log | head -10
done
echo "== $(date +%T) $SEG train/eval done"
