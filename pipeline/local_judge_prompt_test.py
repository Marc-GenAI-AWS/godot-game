"""Does a better prompt make a local model a usable judge?

    .venv/bin/python local_judge_prompt_test.py --anchor anchors/anchor2.jsonl --segment water \
        --style calibrated --host http://127.0.0.1:11434 --model qwen3.8-27b

The first attempt used the rubric written for Claude verbatim: the 27B accepted all 24 sky anchors and
ranked layers like Claude only 64% of the time. Two things a smaller model plausibly needs and that
rubric does not give it - explicit score anchors so it knows what a 5 means versus an 8, and an
instruction to look before it scores.

Run it against an anchor set that contains rejections (anchor1: 3 of 28, anchor2: 8 of 24), because a
judge that accepts everything scores perfectly on a set where the human accepted everything.
"""
import argparse
import base64
import json
import re
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import PIPE, read, read_jsonl  # noqa: E402

CALIBRATION = """You are grading ONE layer of a game scene against the brief it was written from.
Everything else in the frames is the normal game and is not yours to judge.

First look: for each frame, write one sentence describing only what you can actually see in it -
colours, how much of the sky is covered, where the light appears to come from, what is on the ground.
Describe the image, not the brief.

Then score each attribute from 0 to 10 on this scale:
  9-10  exemplary: matches the brief precisely; a reviewer would change nothing
  7-8   good: clearly what the brief asked for, with only minor deviation
  5-6   mediocre: recognisably in the right direction, but a clear mismatch in colour, amount or placement
  3-4   poor: contradicts the brief in a way a player would notice
  0-2   wrong: the brief's intent is simply absent

Most layers land between 5 and 7. Reserve 8 or more for a layer with no visible mismatch, and use 4 or
less when you can point at something specific that is wrong. If an attribute cannot be judged from these
frames, score it 5 and say so in its evidence.

Every attribute's evidence must quote something you saw in a frame, not restate the brief.

The overall score should follow the weakest attributes, not the average: a layer with one badly wrong
attribute is not a good example even if everything else is fine.
"""

SCHEMA = """
Reply with JSON only, in this shape:
{"attributes": {"<name>": {"score": 0-10, "evidence": "what you saw"}, ...},
 "overall": 0-10, "pass": true|false, "revision_notes": "what to change"}
"""


def ask(host, model, prompt, frames, timeout=900):
    images = [base64.b64encode(Path(f).read_bytes()).decode() for f in frames[:3]]
    body = {"model": model, "stream": False, "options": {"temperature": 0, "num_ctx": 8192},
            "messages": [{"role": "user", "content": prompt, "images": images}]}
    req = urllib.request.Request(host.rstrip("/") + "/api/chat", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        text = json.load(r)["message"]["content"]
    m = re.search(r"\{(?:[^{}]|\{[^{}]*\})*\}", text[text.find("{"):], re.S) if "{" in text else None
    blob = text[text.find("{"):text.rfind("}") + 1] if "{" in text and "}" in text else None
    for cand in (blob, m.group(0) if m else None):
        if not cand:
            continue
        try:
            return json.loads(cand)
        except Exception:
            continue
    raise ValueError(f"no JSON in the reply: {text[:150]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--anchor", required=True)
    ap.add_argument("--segment", required=True)
    ap.add_argument("--style", choices=["rubric", "calibrated"], default="calibrated")
    # local models run on navani; the RTX PRO hosts only the shared 27B on vLLM (Marc, 2026-09-16)
    ap.add_argument("--host", default="http://127.0.0.1:11434")
    ap.add_argument("--model", default="qwen3.8-27b")
    ap.add_argument("--bar", type=int, default=6)
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()

    rubric = read(PIPE / "rubrics" / f"{a.segment}.md")
    rows = read_jsonl(a.anchor)[:a.limit or None]
    out = []
    for i, r in enumerate(rows, 1):
        frames = [f["path"] if isinstance(f, dict) else f for f in r["frames"]]
        frames = [f for f in frames if Path(f).exists()]
        if not frames:
            print(f"  {r['id']}: frames missing, skipped"); continue
        brief = "\n\nBrief:\n" + json.dumps({k: v for k, v in r["brief"].items() if k != "id"}, indent=2)
        prompt = (CALIBRATION + "\n" + rubric + brief + SCHEMA) if a.style == "calibrated" else \
                 (rubric + brief + "\n\nScore the candidate frames against the brief. JSON only.")
        try:
            j = ask(a.host, a.model, prompt, frames)
        except Exception as e:
            print(f"  {r['id']}: failed ({str(e)[:80]})"); continue
        o = j.get("overall")
        o = o if isinstance(o, (int, float)) else None
        rec = {"id": r["id"], "human": r["human_pass"], "local": o,
               "local_pass": None if o is None else o >= a.bar,
               "claude": (list(r.get("judge_verdicts", {}).values()) or [{}])[0].get("overall")}
        out.append(rec)
        mark = "ok " if rec["local_pass"] == rec["human"] else "MISS"
        print(f"  [{i}/{len(rows)}] {r['id']}: local {o} -> {'accept' if rec['local_pass'] else 'reject'} | "
              f"human {'accept' if rec['human'] else 'reject'}  {mark}", flush=True)

    Path(a.anchor).with_suffix(f".local-{a.style}.jsonl").write_text("".join(json.dumps(r) + "\n" for r in out))
    scored = [r for r in out if r["local"] is not None]
    if not scored:
        print("no usable verdicts"); return
    rej = [r for r in scored if not r["human"]]
    acc = [r for r in scored if r["human"]]
    print(f"\n{a.style} prompt, {len(scored)} anchors, bar >={a.bar}")
    print(f"  agrees with the human: {sum(1 for r in scored if r['local_pass'] == r['human'])}/{len(scored)}")
    if rej:
        print(f"  catches the layers the human rejected: {sum(1 for r in rej if not r['local_pass'])}/{len(rej)}")
    if acc:
        print(f"  keeps the layers the human accepted:   {sum(1 for r in acc if r['local_pass'])}/{len(acc)}")
    import collections
    print("  score spread:", dict(sorted(collections.Counter(r["local"] for r in scored).items())))


if __name__ == "__main__":
    main()
