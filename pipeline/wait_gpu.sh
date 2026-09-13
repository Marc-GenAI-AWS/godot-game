#!/bin/bash
# Wait until no other user's compute process holds the GPU (shared dev box), then
# return. Max wait in minutes as $1 (default 90); after that, proceed anyway.
MAX=${1:-90}
for i in $(seq 1 $((MAX*2))); do
  others=$(nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader 2>/dev/null | awk -F', ' '{print $1}' | while read p; do u=$(ps -o user= -p $p 2>/dev/null); [ -n "$u" ] && [ "$u" != "$USER" ] && echo $p; done | wc -l)
  if [ "$others" -eq 0 ]; then echo "gpu free after $((i/2)) min"; exit 0; fi
  sleep 30
done
echo "gpu still shared after $MAX min; proceeding"
