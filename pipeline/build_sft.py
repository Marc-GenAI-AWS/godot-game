"""Turn verified candidates into SFT data (chat JSONL) with a held-out split.

    python3 pipeline/build_sft.py --verified runs/sky1/verified.jsonl [runs/sky1/verified_rev.jsonl ...] \
        --out runs/sky1/sft --val-frac 0.15

Each example: system = contract, user = brief prompt (or revision prompt),
assistant = the layer that passed. Fails are kept aside as preference data
(chosen = a passing sibling for the same brief, rejected = the fail).
"""
import argparse
import json
import random
from collections import defaultdict
from pathlib import Path

from common import PIPE, read, read_jsonl, write_jsonl


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verified", nargs="+", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--val-frac", type=float, default=0.15)
    ap.add_argument("--seed", type=int, default=0)
    a = ap.parse_args()
    rows = []
    for p in a.verified:
        rows += read_jsonl(p)
    by_brief = defaultdict(list)
    for r in rows:
        by_brief[r["brief_id"]].append(r)
    contracts = {}
    examples, prefs = [], []
    for bid, rs in by_brief.items():
        seg = rs[0]["segment"]
        if seg not in contracts:
            contracts[seg] = read(PIPE / "contract" / f"{seg}.md")
        passes = [r for r in rs if r["pass"]]
        fails = [r for r in rs if not r["pass"]]
        for r in passes:
            examples.append({
                "brief_id": bid, "segment": seg, "mode": r.get("mode", "write"), "score": r["score"],
                "messages": [
                    {"role": "system", "content": contracts[seg]},
                    {"role": "user", "content": r["prompt"]},
                    {"role": "assistant", "content": "```gdscript\n" + read(r["path"]) + "```"},
                ]})
        if passes and fails:
            best = max(passes, key=lambda r: r["score"])
            for f in fails:
                prefs.append({"brief_id": bid, "segment": seg, "prompt": f["prompt"],
                              "chosen": read(best["path"]), "rejected": read(f["path"]),
                              "rejected_evidence": f["evidence"]})
    rng = random.Random(a.seed)
    briefs = sorted(by_brief.keys())
    rng.shuffle(briefs)
    n_val = max(1, int(len(briefs) * a.val_frac)) if len(briefs) > 3 else 0
    val_ids = set(briefs[:n_val])
    train = [e for e in examples if e["brief_id"] not in val_ids]
    val = [e for e in examples if e["brief_id"] in val_ids]
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    write_jsonl(out / "train.jsonl", train)
    write_jsonl(out / "val.jsonl", val)
    write_jsonl(out / "preferences.jsonl", prefs)
    write_jsonl(out / "heldout_briefs.jsonl", [by_brief[b][0]["brief"] for b in sorted(val_ids)])
    stats = {"briefs": len(briefs), "examples": len(examples), "train": len(train), "val": len(val),
             "preference_pairs": len(prefs), "pass_rate": round(sum(1 for r in rows if r["pass"]) / max(1, len(rows)), 3)}
    (out / "stats.json").write_text(json.dumps(stats, indent=2))
    print(json.dumps(stats))


if __name__ == "__main__":
    main()
