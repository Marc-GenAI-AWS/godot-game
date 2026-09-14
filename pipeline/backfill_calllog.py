"""Backfill runs/_calls/judge.jsonl from judgements made before full call logging.

    pipeline/.venv/bin/python pipeline/backfill_calllog.py

Records have type "backfill": the parsed verdict, checks and pass, with the candidate
frames stored by hash. The rubric text, prompt blocks, raw reply and reference frames
were not kept then, so those fields are null. Only current verified*.jsonl files are
read: backups (*.pre_*, *.oom_partial, old_*/ folders) point at captures that have been
re-rendered since. Safe to re-run; rows already backfilled are skipped.
"""
import glob
import json
import os
from pathlib import Path

from calllog import CALLS, log_call, store_image
from common import RUNS


def main():
    done = set()
    judge_log = CALLS / "judge.jsonl"
    if judge_log.exists():
        for line in open(judge_log):
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                continue
            if r.get("type") == "backfill":
                done.add((r.get("run"), r.get("file"), r.get("candidate")))
    n = skipped = 0
    for f in sorted(glob.glob(str(RUNS / "*" / "verified*.jsonl"))):
        p = Path(f)
        if p.parent.name.startswith("_") or not p.name.endswith(".jsonl"):
            continue
        for line in open(p):
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                continue
            j = r.get("judge") or {}
            frames = r.get("frames") or []
            if not j.get("attributes") or not frames or not all(os.path.exists(x) for x in frames):
                skipped += 1
                continue
            key = (p.parent.name, p.name, r["candidate"])
            if key in done:
                continue
            brief = r.get("brief") or {}
            log_call("judge", {"type": "backfill", "run": p.parent.name, "file": p.name, "candidate": r["candidate"],
                               "brief_id": r.get("brief_id"), "mode": r.get("mode"), "segment": r.get("segment"),
                               "world": brief.get("world"), "brief": brief, "model": None, "system": None,
                               "blocks": None, "reply": None, "repair_reply": None, "reference": None,
                               "frames": [{"image": store_image(x), "path": x} for x in frames],
                               "verdict": {k: v for k, v in j.items() if k != "usage"}, "usage": j.get("usage"),
                               "checks": r.get("checks"), "pass": r.get("pass"), "score": r.get("score")})
            done.add(key)
            n += 1
    print(f"backfilled {n} judgements; skipped {skipped} rows without a judgement or frames on disk")


if __name__ == "__main__":
    main()
