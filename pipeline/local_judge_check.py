"""Score a local vision model as a candidate judge, against Marc's labels and Claude's verdicts.

    .venv/bin/python local_judge_check.py --anchor runs/anchor3 --run sky3 --segment sky \
        --host http://127.0.0.1:11434 --model qwen3.8-27b

The judge is the quality anchor for the whole pipeline, so a local replacement has to be measured,
not assumed. Every anchor item has three things already: the frames, Claude's stored verdict, and a
human label. This sends the same prompt and images to a local model and reports:

  * agreement with the human labels  - the only ground truth we have
  * agreement with Claude at the same bar - does it accept and reject the same layers
  * score correlation - does it rank layers the same way even if its scale differs

Costs nothing and renders nothing: the frames are already on disk.
"""
import argparse
import base64
import json
import re
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import PIPE, SEGMENTS, read, read_jsonl  # noqa: E402
from verify import judge_pass  # noqa: E402


def local_judge(host: str, model: str, segment: str, brief: dict, frames: list, timeout: int = 900) -> dict:
    """Same brief, same rubric, same frames as verify.judge sends to Claude."""
    rubric = read(PIPE / "rubrics" / f"{segment}.md")
    prompt = (rubric + "\n\nBrief:\n" + json.dumps({k: v for k, v in brief.items() if k != "id"}, indent=2) +
              "\n\nScore the candidate frames against the brief. Reply with JSON only.")
    images = [base64.b64encode(Path(f).read_bytes()).decode() for f in frames[:3]]
    body = {"model": model, "stream": False, "options": {"temperature": 0},
            "messages": [{"role": "user", "content": prompt, "images": images}]}
    req = urllib.request.Request(host.rstrip("/") + "/api/chat", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        text = json.load(r)["message"]["content"]
    m = re.search(r"\{.*\}", text, re.S)
    if not m:
        raise ValueError(f"no JSON in the reply: {text[:160]}")
    return json.loads(m.group(0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--anchor", required=True, help="an anchor directory with key.json")
    ap.add_argument("--run", required=True, help="the run whose verified.jsonl holds the frames and Claude's verdicts")
    ap.add_argument("--segment", required=True)
    ap.add_argument("--labels", help="the human label line, e.g. 'anchor3 S01P S02F ...' (default: anchors/<name>.jsonl)")
    # local models run on navani; the RTX PRO hosts only the shared 27B on vLLM (Marc, 2026-09-16)
    ap.add_argument("--host", default="http://127.0.0.1:11434")
    ap.add_argument("--model", default="qwen3.8-27b")
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()

    key = json.loads((Path(a.anchor) / "key.json").read_text())
    rows = {r["candidate"]: r for r in read_jsonl(f"runs/{a.run}/verified.jsonl")}
    human = {}
    if a.labels:
        human = {t[:3]: t[3] == "P" for t in a.labels.split() if len(t) == 4}
    else:
        p = Path("anchors") / (Path(a.anchor).name + ".jsonl")
        if p.exists():
            human = {r["id"]: r["marc"] for r in read_jsonl(p)}

    items = list(key.items())[:a.limit or None]
    out, failures = [], 0
    for i, (sid, meta) in enumerate(items, 1):
        row = rows.get(meta["candidate"])
        if not row or not row.get("frames"):
            print(f"  {sid}: no frames on disk, skipped"); continue
        try:
            j = local_judge(a.host, a.model, a.segment, row["brief"], row["frames"])
        except Exception as e:
            failures += 1
            print(f"  {sid}: local judge failed ({str(e)[:90]})")
            continue
        overall = j.get("overall")
        rec = {"id": sid, "candidate": meta["candidate"], "claude": meta["judge"],
               "local": overall if isinstance(overall, int) else None,
               "claude_pass": judge_pass(a.segment, {"overall": meta["judge"], "pass": meta["judge_pass"],
                                                     "attributes": {}}),
               "local_pass": judge_pass(a.segment, j) if isinstance(overall, int) else None,
               "human": human.get(sid)}
        out.append(rec)
        print(f"  [{i}/{len(items)}] {sid}: local {rec['local']} vs Claude {rec['claude']}"
              f"{'' if rec['human'] is None else ' | human ' + ('accept' if rec['human'] else 'reject')}", flush=True)

    Path(a.anchor, "local_judge.jsonl").write_text("".join(json.dumps(r) + "\n" for r in out))
    scored = [r for r in out if r["local"] is not None]
    if not scored:
        print("no usable local verdicts"); return
    both = [r for r in scored if r["human"] is not None]
    print(f"\n{len(scored)} judged locally ({failures} failed)")
    if both:
        lh = sum(1 for r in both if r["local_pass"] == r["human"])
        ch = sum(1 for r in both if r["claude_pass"] == r["human"])
        print(f"  agreement with the human labels: local {lh}/{len(both)}, Claude {ch}/{len(both)}")
    agree = sum(1 for r in scored if r["local_pass"] == r["claude_pass"])
    print(f"  agrees with Claude's accept/reject: {agree}/{len(scored)}")
    dif = [r["local"] - r["claude"] for r in scored]
    print(f"  score offset (local minus Claude): mean {sum(dif)/len(dif):+.2f}, "
          f"range {min(dif):+d} to {max(dif):+d}")
    pairs = [(r["claude"], r["local"]) for r in scored]
    conc = dis = 0
    for i in range(len(pairs)):
        for k in range(i + 1, len(pairs)):
            a1, b1 = pairs[i]; a2, b2 = pairs[k]
            if a1 == a2 or b1 == b2: continue
            conc += (a1 < a2) == (b1 < b2); dis += (a1 < a2) != (b1 < b2)
    if conc + dis:
        print(f"  ranks layers the same way as Claude: {conc/(conc+dis)*100:.0f}% of comparable pairs")


if __name__ == "__main__":
    main()
