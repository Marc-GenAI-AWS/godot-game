"""Recovery: rebuild revisions.jsonl from the *r.gd files on disk when the
revise stage did not finish (same rows teacher.py --revise would have written)."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import read, read_jsonl, write_jsonl
from teacher import revise_prompt

run = Path(sys.argv[1])
rows = []
for r in read_jsonl(run / "verified.jsonl"):
    if r.get("pass"):
        continue
    cid = r["candidate"] + "r"
    p = run / "candidates" / f"{cid}.gd"
    if not p.exists():
        continue
    rows.append({"candidate": cid, "brief_id": r["brief_id"], "brief": r["brief"], "segment": r["segment"],
                 "mode": "revise", "prompt": revise_prompt(r["brief"], read(r["path"]), r.get("evidence", "")),
                 "parent": r["candidate"], "path": str(p)})
write_jsonl(run / "revisions.jsonl", rows)
print(f"rebuilt {len(rows)} revision rows -> {run / 'revisions.jsonl'}")
