"""The agentic loop: scene brief -> director -> specialists -> verifier -> revise -> accept.

    python3 pipeline/loop/director.py "a foggy dawn on the street, sun low behind the walker" \
        --out pipeline/runs/loop1 --backend teacher            # specialists stood in by Claude
    ... --backend local:http://127.0.0.1:8000/v1 --model sky-sft   # the fine-tuned specialist
    ... --backend endpoint:scene-sky-specialist                     # a SageMaker endpoint

The director (Claude on Bedrock) turns the scene brief into per-segment
briefs in the schema the specialists were trained on. Each specialist writes
its layer, the verifier scores it, and evidence goes back as a revision brief
for up to --rounds rounds. Segments without a trained specialist keep the
shipped gold layer. The accepted layers are installed under
game/segments/<segment>/generated/<run>.gd and the world can be played with
#world=<world>&swap=<segment>:res://segments/<segment>/generated/<run>.gd
"""
import argparse
import json
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import DIRECTOR_MODEL, GAME, SEGMENTS, converse, parse_json, read_jsonl, write_jsonl  # noqa: E402
from specialist import Specialist  # noqa: E402
from verify import verify_one  # noqa: E402

DIRECTOR_SYSTEM = """You are the director of a procedural game-scene studio. You turn a one-line
scene brief into precise per-segment briefs for specialist models. Available
worlds: "beach" (a resort shoreline, walker heads -Z, sea at +X) and "street"
(a suburban two-lane road, driver heads -Z). Only these segments have
specialists right now: {segments}. Every other segment keeps its shipped layer.

Reply with JSON only:
{{"world": "beach" | "street",
  "summary": "one sentence of the intended look",
  "segments": {{"sky": {{"segment": "sky", "world": "...", "time_of_day": "dawn|morning|noon|afternoon|golden hour|dusk|night",
     "weather": "clear|scattered clouds|broken clouds|overcast|hazy", "sun_elevation_deg": 0.0, "sun_azimuth_deg": 0.0,
     "cloud_cover": 0.0, "haze": 0.0, "wind_strength": 1.0, "palette_words": ["..."], "mood": "...", "text": "one or two sentences"}}}}}}

Azimuth is where the sun sits: 0 = ahead of the walker (-Z), 90 = +X (sea side / right kerb), 180 = behind.
Keep values physically consistent (night: negative elevation; overcast: cover >= 0.85)."""


def direct(scene_brief: str, segments: list, run: str = "") -> dict:
    system = DIRECTOR_SYSTEM.format(segments=", ".join(segments))
    user = "Scene brief: " + scene_brief
    text, usage = converse(DIRECTOR_MODEL, system, [{"text": user}], max_tokens=1500)
    try:   # full record for training a local director later (calllog.py); logged before parsing so bad replies are kept too
        from calllog import log_call
        log_call("director", {"type": "plan", "run": run, "scene_brief": scene_brief, "segments": segments,
                              "model": DIRECTOR_MODEL, "system": system, "user": user, "reply": text, "usage": usage})
    except Exception as e:
        print(f"  calllog: director call not logged ({str(e)[:160]})", flush=True)
    plan = parse_json(text)
    for seg, b in plan["segments"].items():
        b.setdefault("segment", seg)
        b.setdefault("world", plan["world"])
        b["id"] = f"loop-{seg}-{int(time.time())}"
    return plan


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scene_brief")
    ap.add_argument("--out", required=True)
    ap.add_argument("--backend", default="teacher")
    ap.add_argument("--model")
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--segments", default="sky")
    a = ap.parse_args()
    out = Path(a.out)
    (out / "candidates").mkdir(parents=True, exist_ok=True)
    segments = a.segments.split(",")

    print("director:", DIRECTOR_MODEL)
    plan = direct(a.scene_brief, segments, run=out.name)
    (out / "plan.json").write_text(json.dumps(plan, indent=2))
    print(" ", plan["summary"])
    log = []
    accepted = {}
    for seg in segments:
        brief = plan["segments"][seg]
        sp = Specialist(seg, a.backend, a.model)
        code, prompt = sp.write(brief)
        res = None
        for rnd in range(a.rounds):
            cid = f"{brief['id']}_r{rnd}"
            path = out / "candidates" / f"{cid}.gd"
            path.write_text(code)
            row = {"candidate": cid, "brief_id": brief["id"], "brief": brief, "segment": seg, "path": str(path),
                   "mode": "write" if rnd == 0 else "revise", "prompt": prompt}
            res = verify_one(row, out)
            log.append(res)
            print(f"  {seg} round {rnd}: {'PASS' if res['pass'] else 'fail'} score {res['score']:.2f} "
                  f"judge {res.get('judge', {}).get('overall', '-')}")
            if res["pass"]:
                break
            print("   ", res["evidence"].splitlines()[-1][:200])
            code, prompt = sp.revise(brief, code, res["evidence"])
        if res and res["pass"]:
            dest = GAME / "segments" / seg / "generated"
            dest.mkdir(parents=True, exist_ok=True)
            name = out.name
            shutil.copy(res["path"], dest / f"{name}.gd")
            accepted[seg] = f"res://segments/{seg}/generated/{name}.gd"
    write_jsonl(out / "log.jsonl", log)
    report = {"scene_brief": a.scene_brief, "world": plan["world"], "accepted": accepted,
              "unresolved": [s for s in segments if s not in accepted],
              "play": f"#world={plan['world']}" + "".join(f"&swap={s}:{p}" for s, p in accepted.items())}
    (out / "report.json").write_text(json.dumps(report, indent=2))
    try:   # how the plan turned out: the label a local director is judged by
        from calllog import log_call
        log_call("director", {"type": "outcome", "run": out.name, "scene_brief": a.scene_brief, "backend": a.backend,
                              "plan": plan, "accepted": accepted, "unresolved": report["unresolved"],
                              "rounds": [{"candidate": r["candidate"], "mode": r.get("mode"), "pass": r["pass"],
                                          "score": r["score"], "judge_overall": (r.get("judge") or {}).get("overall")}
                                         for r in log]})
    except Exception as e:
        print(f"  calllog: loop outcome not logged ({str(e)[:160]})", flush=True)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
