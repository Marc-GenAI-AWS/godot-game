"""The verifier: static gate -> runtime gate -> checks -> capture -> judge -> aggregate.

    python3 pipeline/verify.py --candidates runs/sky1/candidates.jsonl --out runs/sky1
    python3 pipeline/verify.py --file some_layer.gd --segment sky --brief '{"...": ...}'

One pipeline serves three consumers: data filtering (pass flag), training
(score in [0, 1]) and the director's acceptance test (evidence strings).
Gates veto: a failed gate scores 0 regardless of the judge.

Rendering is native (Godot on the local GPU display) when DISPLAY is set,
which takes seconds; the browser harness in shots/ is the fallback recipe.
"""
import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from common import (GAME, GODOT, JUDGE_MODEL, PIPE, SEGMENTS, converse, image_block, parse_json, read,
                    read_jsonl, write_jsonl)

FORBIDDEN = ["OS.", "FileAccess", "DirAccess", "HTTPRequest", "JavaScriptBridge", "get_tree().quit",
             "load(", "preload(", "class_name "]
BASELINE = {}   # world -> stats without overrides
GPU_LOCK = threading.RLock()   # one native capture at a time; gates and judge calls overlap


# ---------------------------------------------------------------- gates ---

def static_gate(code: str) -> list:
    problems = []
    if not code.lstrip().startswith("extends SceneLayer"):
        problems.append("file must start with 'extends SceneLayer'")
    if "func build(" not in code:
        problems.append("no build() function")
    for tok in FORBIDDEN:
        if tok in code:
            problems.append(f"forbidden token: {tok.strip()}")
    if len(code) > 20000:
        problems.append("file longer than 20k chars")
    return problems


def install_candidate(segment: str, cid: str, code: str) -> str:
    d = GAME / "segments" / segment / "candidates"
    d.mkdir(parents=True, exist_ok=True)
    (d / f"{cid}.gd").write_text(code)
    return f"res://segments/{segment}/candidates/{cid}.gd"


def godot(args, timeout, display=None):
    env = dict(os.environ)
    if display:
        env["DISPLAY"] = display
    p = subprocess.run([str(GODOT), "--path", str(GAME)] + args, capture_output=True, text=True,
                       timeout=timeout, env=env)
    return p.stdout + p.stderr + f"\n[exit {p.returncode}]"


def runtime_gate(world: str, swap: str) -> tuple:
    out = godot(["--headless", "--quit-after", "90", "--", f"--world={world}", f"--swap={swap}"], timeout=180)
    errors = [l.strip() for l in out.splitlines() if "SCRIPT ERROR" in l or l.startswith("ERROR") or "Parse Error" in l]
    ready = "world ready" in out
    if not ready and not errors:
        errors.append("scene never reported 'world ready'")
    return (len(errors) == 0, errors[:6])


# --------------------------------------------------------------- capture ---

def capture(world: str, swap: str, out_dir: Path, shots: str, script: str) -> dict:
    display = os.environ.get("DISPLAY") or ":0"
    out_dir = Path(out_dir).resolve()          # Godot chdirs into the project; relative paths would land there
    out_dir.mkdir(parents=True, exist_ok=True)
    args = ["--resolution", "1280x720", "--", f"--world={world}", f"--capture={out_dir}", f"--shots={shots}"]
    if script:
        args.append(f"--script={script}")
    if swap:
        args.append(f"--swap={swap}")
    out = godot(args, timeout=240, display=display)
    stats_p = out_dir / "stats.json"
    if not stats_p.exists():
        raise RuntimeError("capture produced no stats.json (args %s):\n%s" % (args, out[-800:]))
    stats = json.loads(stats_p.read_text())
    stats["frames"] = sorted(str(p) for p in out_dir.glob(f"{world}_*s.png"))
    return stats


def baseline(world: str, shots: str, script: str) -> dict:
    if world not in BASELINE:
        d = PIPE / "runs" / "_baseline" / world
        p = d / "stats.json"
        if p.exists():
            st = json.loads(p.read_text())
            st["frames"] = sorted(str(x) for x in d.glob(f"{world}_*s.png"))
        else:
            st = capture(world, "", d, shots, script)
        BASELINE[world] = st
    return BASELINE[world]


# ---------------------------------------------------------------- checks ---

def sky_checks(brief: dict, stats: dict, base: dict) -> tuple:
    """Numeric facts a sky layer must get right. Returns (score 0..1, notes)."""
    notes, scores = [], []
    pal = stats["palette"]
    sd = pal["sun_dir"]
    elev = math.degrees(math.asin(max(-1.0, min(1.0, -sd[1]))))
    want = brief.get("sun_elevation_deg", 45.0)
    d = abs(elev - want)
    s = max(0.0, 1.0 - d / 25.0)
    scores.append(s)
    notes.append(f"sun elevation {elev:.0f} deg vs brief {want:.0f} ({'ok' if d < 8 else 'off by %.0f' % d})")
    # azimuth of the sun's position: 0 = towards -Z, 90 = +X (light travels the other way)
    az = (math.degrees(math.atan2(-sd[0], sd[2])) + 360.0) % 360.0
    want_az = brief.get("sun_azimuth_deg", 0.0)
    da = min(abs(az - want_az), 360 - abs(az - want_az))
    scores.append(max(0.0, 1.0 - da / 60.0))
    notes.append(f"sun azimuth {az:.0f} vs brief {want_az:.0f} ({'ok' if da < 20 else 'off by %.0f' % da})")
    # palette published (changed from the defaults unless it's the default kind of day)
    default = [0.1, 0.32, 0.82]
    moved = sum(abs(a - b) for a, b in zip(pal["sky_zenith"], default)) > 0.05
    if brief.get("time_of_day") in ("noon", "morning") and brief.get("weather") == "clear":
        scores.append(1.0)
    else:
        scores.append(1.0 if moved else 0.3)
        notes.append("palette published" if moved else "sky_zenith left at the default")
    # budget
    added = stats["draw_calls"] - base["draw_calls"]
    scores.append(1.0 if added <= 40 else max(0.0, 1.0 - (added - 40) / 80.0))
    notes.append(f"draw calls {added:+d} vs the shipped sky (budget +40), fps {stats['fps_avg']:.0f}")
    if stats["fps_avg"] < 60:
        scores.append(0.3)
        notes.append("below 60 fps")
    # night must not be black: mean brightness of the tilted-up frame
    try:
        from PIL import Image
        im = Image.open(stats["frames"][1]).convert("L").resize((64, 36))
        top = sum(im.getpixel((x, y)) for x in range(64) for y in range(12)) / (64 * 12) / 255.0
        tod = brief.get("time_of_day")
        if tod == "night":
            ok = 0.02 < top < 0.35
        elif tod in ("dusk", "dawn"):
            ok = 0.08 < top < 0.7
        else:
            ok = top > 0.25
        scores.append(1.0 if ok else 0.2)
        notes.append(f"upper-sky brightness {top:.2f} ({'plausible' if ok else 'implausible'} for {tod})")
    except Exception as e:
        notes.append(f"brightness check skipped: {e}")
    return sum(scores) / len(scores), notes


CHECKS = {"sky": sky_checks}


# ----------------------------------------------------------------- judge ---

def judge(segment: str, brief: dict, frames: list) -> dict:
    rubric = read(PIPE / "rubrics" / f"{segment}.md")
    blocks = [{"text": "Brief:\n" + json.dumps({k: v for k, v in brief.items() if k != "id"}, indent=2)}]
    for i, f in enumerate(frames):
        blocks.append({"text": f"Frame {i + 1} ({['default view', 'tilted up', 'side view'][i] if i < 3 else 'extra'}):"})
        blocks.append(image_block(f))
    blocks.append({"text": "Score the frames against the brief. JSON only."})
    text, usage = converse(JUDGE_MODEL, rubric, blocks, max_tokens=3000)
    try:
        j = parse_json(text)
    except Exception as e:
        # one repair round: the same judge, shown its own reply and the parse error
        blocks2 = blocks + [{"text": "Your previous reply could not be parsed as JSON (%s). Reply again with the "
                                     "same judgement as strictly valid JSON only, escaping quotes inside strings:\n%s" % (e, text[:6000])}]
        text2, usage2 = converse(JUDGE_MODEL, rubric, blocks2, max_tokens=3000)
        usage = {k: usage.get(k, 0) + usage2.get(k, 0) for k in set(usage) | set(usage2)}
        try:
            j = parse_json(text2)
        except Exception:
            j = {"attributes": {}, "overall": 0, "pass": False, "revision_notes": "judge reply was not JSON: " + text2[:300]}
    j["usage"] = usage
    return j


# ------------------------------------------------------------- aggregate ---

def verify_one(row: dict, out_dir: Path, do_judge=True) -> dict:
    segment = row["segment"]
    brief = row["brief"]
    cid = row["candidate"]
    spec = SEGMENTS[segment]
    world = brief.get("world", spec["world"])
    code = read(row["path"])
    res = {"candidate": cid, "brief_id": brief["id"], "segment": segment, "brief": brief, "path": row["path"],
           "mode": row.get("mode", "write"), "prompt": row.get("prompt", ""), "gates": {}, "score": 0.0,
           "pass": False, "evidence": "", "checks": {}, "judge": {}}
    t0 = time.time()
    problems = static_gate(code)
    res["gates"]["static"] = problems
    if problems:
        res["evidence"] = "static gate: " + "; ".join(problems)
        return res
    swap = f"{segment}:{install_candidate(segment, cid, code)}"
    ok, errors = runtime_gate(world, swap)
    res["gates"]["runtime"] = errors
    if not ok:
        res["evidence"] = "runtime gate: " + " | ".join(errors)
        return res
    cap_dir = out_dir / "captures" / cid
    try:
        with GPU_LOCK:
            base = baseline(world, spec["shots"], spec["script"])
            stats = capture(world, swap, cap_dir, spec["shots"], spec["script"])
    except Exception as e:
        res["gates"]["capture"] = [str(e)[:300]]
        res["evidence"] = "capture failed: " + str(e)[:300]
        return res
    res["stats"] = {k: stats[k] for k in ("fps_avg", "draw_calls", "palette")}
    res["frames"] = stats["frames"]
    cscore, notes = CHECKS[segment](brief, stats, base)
    res["checks"] = {"score": cscore, "notes": notes}
    jscore = None
    if do_judge:
        j = judge(segment, brief, stats["frames"])
        res["judge"] = j
        jscore = float(j.get("overall", 0)) / 10.0
    if jscore is None:
        res["score"] = cscore
        res["pass"] = cscore >= 0.7
    else:
        res["score"] = 0.4 * cscore + 0.6 * jscore
        res["pass"] = bool(j.get("pass")) and cscore >= 0.6
    ev = ["checks: " + "; ".join(notes)]
    if do_judge:
        for k, v in res["judge"].get("attributes", {}).items():
            ev.append(f"{k} {v.get('score')}/10: {v.get('evidence', '')}")
        if res["judge"].get("revision_notes"):
            ev.append("revise: " + res["judge"]["revision_notes"])
    res["evidence"] = "\n".join(ev)
    res["seconds"] = round(time.time() - t0, 1)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--candidates", help="candidates.jsonl / revisions.jsonl from teacher.py")
    ap.add_argument("--file", help="verify one layer file")
    ap.add_argument("--segment", default="sky")
    ap.add_argument("--brief", help="brief JSON (with --file)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--no-judge", action="store_true")
    ap.add_argument("--name", default="verified.jsonl")
    ap.add_argument("--workers", type=int, default=3, help="candidates in flight (captures are still one at a time)")
    a = ap.parse_args()
    out_dir = Path(a.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    if a.file:
        brief = json.loads(a.brief) if a.brief else {"id": "adhoc", "segment": a.segment, "world": SEGMENTS[a.segment]["world"]}
        rows = [{"candidate": Path(a.file).stem, "segment": a.segment, "brief": brief, "path": a.file}]
    else:
        rows = read_jsonl(a.candidates)
    results = []
    done = 0
    lock = threading.Lock()

    def work(row):
        nonlocal done
        r = verify_one(row, out_dir, do_judge=not a.no_judge)
        with lock:
            done += 1
            results.append(r)
            j = r.get("judge", {})
            print(f"[{done}/{len(rows)}] {r['candidate']}: {'PASS' if r['pass'] else 'fail'} score {r['score']:.2f} "
                  f"checks {r['checks'].get('score', 0):.2f} judge {j.get('overall', '-')} ({r.get('seconds', 0)}s)", flush=True)
            if not r["pass"]:
                print("      " + r["evidence"].splitlines()[0][:160], flush=True)
            if done % 10 == 0:
                write_jsonl(out_dir / a.name, results)   # checkpoint
        return r

    with ThreadPoolExecutor(max(1, a.workers)) as ex:
        list(ex.map(work, rows))
    results.sort(key=lambda r: r["candidate"])
    write_jsonl(out_dir / a.name, results)
    n_pass = sum(1 for r in results if r["pass"])
    print(f"{n_pass}/{len(results)} passed -> {out_dir / a.name}")


if __name__ == "__main__":
    main()
