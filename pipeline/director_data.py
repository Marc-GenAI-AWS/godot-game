"""Director training data: scene brief -> plan, graded by the director verifier.

    python3 pipeline/director_data.py --briefs runs/dir1/scene_briefs.jsonl --out runs/dir1 --workers 6
    python3 pipeline/director_data.py --build-sft runs/dir1 --out runs/dir1/sft

The teacher director (Claude on Bedrock) plans each scene brief. Grading needs no
GPU and no game: the plan must parse, cover every segment, pick the world the brief
describes, use the trained vocabulary exactly (no snapping), and keep the sky
physically consistent with the time of day and weather the brief asks for. Plans
that pass become SFT examples for a local director.
"""
import argparse
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "loop"))

from briefs import TIMES, WEATHER  # noqa: E402
from common import DIRECTOR_MODEL, converse, parse_json, read_jsonl, write_jsonl  # noqa: E402
from director import build_brief, system_prompt  # noqa: E402

SEGMENTS = ["sky", "ground", "vegetation", "props"]
TOL_ELEV = 8.0      # degrees outside the time-of-day band before it counts as wrong
TOL_COVER = 0.15    # cloud cover outside the weather band


def check_plan(plan: dict, intent: dict, segments: list) -> list:
    """Everything wrong with a plan, in plain words. An empty list means it passes."""
    bad = []
    if plan.get("world") != intent["world"]:
        bad.append(f"world {plan.get('world')!r}, the brief describes the {intent['world']}")
    if not (plan.get("summary") or "").strip():
        bad.append("no summary")
    raw = plan.get("segments") or {}
    for seg in segments:
        if seg not in raw or not raw[seg]:
            bad.append(f"{seg}: missing from the plan")
    world = plan.get("world") if plan.get("world") in ("beach", "street") else intent["world"]
    fixes = []
    for seg in segments:
        if raw.get(seg):
            try:
                build_brief(seg, raw[seg], world, "check", fixes)
            except Exception as e:
                bad.append(f"{seg}: brief could not be built ({str(e)[:80]})")
    bad += [f"not a trained value - {f}" for f in fixes]
    # the fields the brief actually describes must come back as the value those words mean
    for e in intent.get("expect", []):
        if e["segment"] not in segments:
            continue
        got = (raw.get(e["segment"]) or {}).get(e["field"])
        if got != e["value"]:
            bad.append(f"{e['segment']}.{e['field']} {got!r} for {e['phrase']!r}, expected {e['value']!r}")
    sky = raw.get("sky") or {}
    if sky:
        tod, wx = sky.get("time_of_day"), sky.get("weather")
        if tod != intent["time_of_day"]:
            bad.append(f"sky.time_of_day {tod!r}, the brief says {intent['time_of_day']!r}")
        if wx != intent["weather"]:
            bad.append(f"sky.weather {wx!r}, the brief says {intent['weather']!r}")
        elev, cover = sky.get("sun_elevation_deg"), sky.get("cloud_cover")
        band = TIMES.get(tod, {}).get("elev")
        if band and isinstance(elev, (int, float)) and not (band[0] - TOL_ELEV <= elev <= band[1] + TOL_ELEV):
            bad.append(f"sun elevation {elev} is outside {tod} ({band[0]}-{band[1]} degrees)")
        cband = WEATHER.get(wx, {}).get("cover")
        if cband and isinstance(cover, (int, float)) and not (cband[0] - TOL_COVER <= cover <= cband[1] + TOL_COVER):
            bad.append(f"cloud cover {cover} is outside {wx} ({cband[0]}-{cband[1]})")
        az = sky.get("sun_azimuth_deg")
        if isinstance(az, (int, float)) and not (-360 <= az <= 360):
            bad.append(f"sun azimuth {az} is not a bearing")
        if not (sky.get("text") or "").strip():
            bad.append("sky: no text")
    return bad


def plan_one(row: dict, segments: list, model: str, run: str) -> dict:
    system = system_prompt(segments)
    user = "Scene brief: " + row["text"]
    text, usage = converse(model, system, [{"text": user}], max_tokens=2500)
    try:
        from calllog import log_call
        log_call("director", {"type": "data", "run": run, "scene_brief": row["text"], "segments": segments,
                              "model": model, "system": system, "user": user, "reply": text, "usage": usage})
    except Exception:
        pass
    out = {"id": row["id"], "scene_brief": row["text"], "intent": row["intent"], "segments": segments,
           "model": model, "usage": usage, "reply": text}
    try:
        plan = parse_json(text)
    except Exception as e:
        out.update({"plan": None, "problems": [f"reply is not JSON ({str(e)[:80]})"], "pass": False})
        return out
    problems = check_plan(plan, row["intent"], segments)
    out.update({"plan": plan, "problems": problems, "pass": not problems})
    print(f"  {row['id']}: {'PASS' if not problems else 'fail - ' + '; '.join(problems)[:110]}", flush=True)
    return out


def canonical(plan: dict, segments: list) -> str:
    """The plan as the director should have written it: same schema, stable key order."""
    raw = plan.get("segments") or {}
    return json.dumps({"world": plan["world"], "summary": plan["summary"],
                       "segments": {s: raw[s] for s in segments if s in raw}}, indent=1)


def build_sft(run_dir: Path, out: Path, val_frac: float):
    rows = [r for r in read_jsonl(run_dir / "planned.jsonl") if r.get("pass")]
    examples = [{"id": r["id"], "messages": [
        {"role": "system", "content": system_prompt(r["segments"])},
        {"role": "user", "content": "Scene brief: " + r["scene_brief"]},
        {"role": "assistant", "content": canonical(r["plan"], r["segments"])}]} for r in rows]
    n_val = max(1, int(len(examples) * val_frac))
    out.mkdir(parents=True, exist_ok=True)
    write_jsonl(out / "val.jsonl", examples[:n_val])
    write_jsonl(out / "train.jsonl", examples[n_val:])
    write_jsonl(out / "heldout_briefs.jsonl", [{"id": r["id"], "text": r["scene_brief"], "intent": r["intent"]}
                                               for r in rows[:n_val]])
    stats = {"planned": len(list(read_jsonl(run_dir / "planned.jsonl"))), "passed": len(rows),
             "train": len(examples) - n_val, "val": n_val}
    (out / "stats.json").write_text(json.dumps(stats, indent=2))
    print(json.dumps(stats))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--briefs")
    ap.add_argument("--out", required=True)
    ap.add_argument("--build-sft", help="a run directory with planned.jsonl")
    ap.add_argument("--segments", default=",".join(SEGMENTS))
    ap.add_argument("--model", default=DIRECTOR_MODEL)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--val-frac", type=float, default=0.12)
    a = ap.parse_args()
    out = Path(a.out)
    if a.build_sft:
        build_sft(Path(a.build_sft), out, a.val_frac)
        return
    segments = a.segments.split(",")
    rows = read_jsonl(a.briefs)
    out.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        planned = list(ex.map(lambda r: plan_one(r, segments, a.model, out.name), rows))
    write_jsonl(out / "planned.jsonl", planned)
    ok = sum(1 for p in planned if p["pass"])
    print(f"{ok}/{len(planned)} plans passed -> {out / 'planned.jsonl'}")
    counts = {}
    for p in planned:
        for prob in p["problems"]:
            counts[prob.split(" -")[0].split(",")[0][:60]] = counts.get(prob.split(" -")[0].split(",")[0][:60], 0) + 1
    for k, v in sorted(counts.items(), key=lambda kv: -kv[1])[:8]:
        print(f"   {v:3d}  {k}")


if __name__ == "__main__":
    main()
