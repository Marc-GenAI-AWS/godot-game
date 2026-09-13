#!/bin/bash
# Start a virtual display with GL, then run whatever command was given
# (default: verify the candidates mounted by the Processing job).
set -e
Xvfb :99 -screen 0 1280x720x24 +extension GLX +render -noreset >/tmp/xvfb.log 2>&1 &
sleep 1
export DISPLAY=:99
cd /work
if [ "$#" -eq 0 ]; then
  exec python3 pipeline/verify.py --candidates /opt/ml/processing/input/candidates.jsonl --out /opt/ml/processing/output
fi
exec "$@"
