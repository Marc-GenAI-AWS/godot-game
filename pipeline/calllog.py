"""Full records of the Claude calls the pipeline depends on (judge, director), kept so
local judge and director models can be trained on them later.

    runs/_calls/judge.jsonl          one line per judge call: rubric, prompt blocks, image hashes,
                                     raw reply (and repair reply), parsed verdict, usage
    runs/_calls/director.jsonl       one line per director plan, one per loop outcome
    runs/_frames/<ab>/<sha256>.png   every image a judge saw, content-addressed: captures are
                                     deleted on re-verify and reference frames are a shared cache

Several verify processes write at once, so appends take a file lock. Logging never raises:
a failure prints a warning and verification carries on. pipeline/archive_calllog.sh copies
both directories to S3.
"""
import fcntl
import hashlib
import json
import os
import threading
import time
from pathlib import Path

from common import RUNS

CALLS = RUNS / "_calls"
FRAMES = RUNS / "_frames"
_lock = threading.Lock()


def store_image(path) -> str:
    data = Path(path).read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    dest = FRAMES / sha[:2] / f"{sha}.png"
    if not dest.exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp = dest.with_name(f"{sha}.tmp{os.getpid()}_{threading.get_ident()}")
        tmp.write_bytes(data)
        os.replace(tmp, dest)
    return sha


def log_blocks(blocks: list, image_paths: list) -> list:
    """Converse user blocks -> log form: text kept, image bytes replaced by the stored hash.
    image_paths lists the image files in the order their blocks appear."""
    out, k = [], 0
    for b in blocks:
        if "text" in b:
            out.append({"text": b["text"]})
        elif "image" in b:
            p = image_paths[k] if k < len(image_paths) else None
            k += 1
            out.append({"image": store_image(p) if p else None, "path": str(p) if p else None})
    return out


def log_call(kind: str, record: dict) -> None:
    try:
        line = json.dumps({"logged_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"), **record}, default=str)
        with _lock:
            CALLS.mkdir(parents=True, exist_ok=True)
            with open(CALLS / f"{kind}.jsonl", "a") as f:
                fcntl.flock(f, fcntl.LOCK_EX)
                f.write(line + "\n")
                f.flush()
                fcntl.flock(f, fcntl.LOCK_UN)
    except Exception as e:
        print(f"  calllog: could not log a {kind} call ({str(e)[:160]})", flush=True)
