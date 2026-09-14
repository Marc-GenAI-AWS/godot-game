#!/bin/bash
# Copy the judge / director call logs and the frames they reference to S3.
#   pipeline/archive_calllog.sh
# Idempotent (aws s3 sync): run it after each data run.
set -euo pipefail
P=$(cd "$(dirname "$0")" && pwd)
BUCKET=${SAGEMAKER_BUCKET:-amazon-sagemaker-605134472325-us-east-2-6df5g199r0fy5l}
REGION=${AWS_REGION:-us-east-2}
DEST=s3://$BUCKET/call-logs
[ -d "$P/runs/_frames" ] && aws s3 sync "$P/runs/_frames" "$DEST/frames" --region "$REGION" --only-show-errors
[ -d "$P/runs/_calls" ] && aws s3 sync "$P/runs/_calls" "$DEST/calls" --region "$REGION" --only-show-errors
echo "archived $(find "$P/runs/_frames" -name '*.png' 2>/dev/null | wc -l) frames and $(cat "$P"/runs/_calls/*.jsonl 2>/dev/null | wc -l) call records to $DEST"
