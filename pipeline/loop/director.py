"""The agentic loop: scene brief -> director -> specialists -> verifier -> revise -> accept.

    python3 pipeline/loop/director.py "a foggy dawn on the street, sun low behind the walker" \
        --out pipeline/runs/loop1 --backend teacher            # specialists stood in by Claude
    ... --backend local:http://127.0.0.1:8000/v1 --model sky-sft   # the fine-tuned specialist
    ... --backend endpoint:scene-sky-specialist                     # a SageMaker endpoint
    ... --segments sky,ground,vegetation \
        --backend sky=hf:~/models/<sky job>,ground=hf:~/models/<ground job>,vegetation=hf:~/models/<veg job> --composite

The director (Claude on Bedrock) turns the scene brief into per-segment
briefs in the schema the specialists were trained on. For sky it writes the
brief itself; for ground and vegetation it picks one trained value per field
and the brief is built by briefs.py, so the prompt matches training exactly.
Each specialist writes its layer, the verifier scores it (each layer alone in
the shipped scene), and evidence goes back as a revision brief for up to
--rounds rounds. Segments without a specialist keep the shipped gold layer.
Accepted layers are installed under game/segments/<segment>/generated/<run>.gd
and the scene plays with all of them at
#world=<world>&swap=<segment>:res://...gd;<segment>:res://...gd
--composite renders the accepted layers together in one capture.
"""
import argparse
import difflib
import json
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from briefs import VOCAB, ground_brief, vegetation_brief  # noqa: E402
from common import DIRECTOR_MODEL, GAME, SEGMENTS, converse, parse_json, write_jsonl  # noqa: E402
from specialist import Specialist  # noqa: E402
from verify import capture, verify_one  # noqa: E402

DIRECTOR_HEAD = """You are the director of a procedural game-scene studio. You turn a one-line
scene brief into precise per-segment briefs for specialist models. Available
worlds: "beach" (a resort shoreline, walker heads -Z, sea at +X) and "street"
(a suburban two-lane road, driver heads -Z). Only these segments have
specialists right now: {segments}. Every other segment keeps its shipped layer.
Make the segments agree with each other and with the scene brief (one time of day, one mood).

Reply with JSON only:
{{"world": "beach" | "street",
  "summary": "one sentence of the intended look",
  "segments": {{{schemas}}}}}"""

SCHEMAS = {
    "sky": ('"sky": {"segment": "sky", "world": "...", "time_of_day": "dawn|morning|noon|afternoon|golden hour|dusk|night",\n'
            '     "weather": "clear|scattered clouds|broken clouds|overcast|hazy", "sun_elevation_deg": 0.0, "sun_azimuth_deg": 0.0,\n'
            '     "cloud_cover": 0.0, "haze": 0.0, "wind_strength": 1.0, "palette_words": ["..."], "mood": "...", "text": "one or two sentences"}'),
    "ground": '"ground": {"tone": "...", "<field>": "... the other fields listed for the chosen world"}',
    "vegetation": '"vegetation": {"density": "...", "species_mix": "...", "size": "...", "hedges": "...", "look": "..."}',
}

SKY_RULES = ("sky: azimuth is where the sun sits: 0 = ahead of the walker (-Z), 90 = +X (sea side / right kerb), 180 = behind.\n"
             "Keep values physically consistent (night: negative elevation; overcast: cover >= 0.85).")


def _rules(seg: str) -> str:
    if seg == "sky":
        return SKY_RULES
    if seg == "ground":
        lines = ["ground: choose exactly one of the listed values for each field, copied exactly, using the fields for the chosen world."]
        for world, fields in VOCAB["ground"].items():
            lines.append(f"  on the {world}: " + "; ".join(f"{k}: " + " | ".join(v) for k, v in fields.items()))
        return "\n".join(lines)
    if seg == "vegetation":
        v = VOCAB["vegetation"]
        lines = ["vegetation: choose exactly one of the listed values for each field, copied exactly."]
        lines += [f"  {k}: " + " | ".join(v[k]) for k in ("density", "size", "hedges", "look")]
        lines += [f"  species_mix on the {w}: " + " | ".join(m) for w, m in v["species_mix"].items()]
        return "\n".join(lines)
    return ""


def system_prompt(segments: list) -> str:
    head = DIRECTOR_HEAD.format(segments=", ".join(segments), schemas=",\n     ".join(SCHEMAS[s] for s in segments))
    return head + "\n\n" + "\n\n".join(r for r in (_rules(s) for s in segments) if r)


def _pick(value, allowed: list, fixes: list, label: str) -> str:
    if value in allowed:
        return value
    near = difflib.get_close_matches(str(value), allowed, n=1, cutoff=0.0) or [allowed[0]]
    fixes.append(f"{label}: {value!r} -> {near[0]!r}")
    return near[0]


def build_brief(seg: str, raw: dict, world: str, bid: str, fixes: list) -> dict:
    if seg == "sky":
        b = dict(raw)
        b.setdefault("segment", seg)
        b["world"] = world
        b["id"] = bid
        return b
    if seg == "vegetation":
        v = VOCAB["vegetation"]
        return vegetation_brief(bid, world,
                                _pick(raw.get("density"), v["density"], fixes, "vegetation.density"),
                                _pick(raw.get("species_mix"), v["species_mix"][world], fixes, "vegetation.species_mix"),
                                _pick(raw.get("size"), v["size"], fixes, "vegetation.size"),
                                _pick(raw.get("hedges"), v["hedges"], fixes, "vegetation.hedges"),
                                _pick(raw.get("look"), v["look"], fixes, "vegetation.look"))
    if seg == "ground":
        fields = VOCAB["ground"][world]
        return ground_brief(bid, world, **{k: _pick(raw.get(k), vals, fixes, f"ground.{k}") for k, vals in fields.items()})
    raise ValueError(f"the director has no brief schema for segment {seg}")


def direct(scene_brief: str, segments: list, run: str = "") -> dict:
    system = system_prompt(segments)
    user = "Scene brief: " + scene_brief
    text, usage = converse(DIRECTOR_MODEL, system, [{"text": user}], max_tokens=2500)
    try:   # full record for training a local director later (calllog.py); logged before parsing so bad replies are kept too
        from calllog import log_call
        log_call("director", {"type": "plan", "run": run, "scene_brief": scene_brief, "segments": segments,
                              "model": DIRECTOR_MODEL, "system": system, "user": user, "reply": text, "usage": usage})
    except Exception as e:
        print(f"  calllog: director call not logged ({str(e)[:160]})", flush=True)
    plan = parse_json(text)
    world = plan.get("world") if plan.get("world") in ("beach", "street") else "beach"
    plan["world"] = world
    ts = int(time.time())
    fixes = []
    raw_segments = plan.get("segments") or {}
    plan["segments"] = {}
    for seg in segments:
        if seg not in raw_segments:
            fixes.append(f"{seg}: missing from the director's plan; segment keeps its shipped layer")
            continue
        plan["segments"][seg] = build_brief(seg, raw_segments[seg] or {}, world, f"loop-{seg}-{ts}", fixes)
    plan["fixes"] = fixes
    return plan


def parse_backends(spec: str, segments: list) -> dict:
    """'teacher' / 'hf:<dir>' for every segment, or 'sky=hf:<dir>,ground=hf:<dir>' per segment."""
    if "=" in spec.split(",")[0].split(":")[0]:
        pairs = dict(item.split("=", 1) for item in spec.split(","))
        return {s: pairs[s] for s in segments if s in pairs}
    return {s: spec for s in segments}


def free_model(sp: Specialist) -> None:
    if getattr(sp, "_hf", None) is not None:
        sp._hf = None
        try:
            import gc
            import torch
            gc.collect()
            torch.cuda.empty_cache()
        except Exception:
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scene_brief")
    ap.add_argument("--out", required=True)
    ap.add_argument("--backend", default="teacher", help="one backend for every segment, or seg=backend pairs joined by commas")
    ap.add_argument("--model")
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--segments", default="sky")
    ap.add_argument("--composite", action="store_true", help="render the accepted layers together")
    a = ap.parse_args()
    out = Path(a.out)
    (out / "candidates").mkdir(parents=True, exist_ok=True)
    segments = a.segments.split(",")
    backends = parse_backends(a.backend, segments)

    print("director:", DIRECTOR_MODEL)
    plan = direct(a.scene_brief, segments, run=out.name)
    (out / "plan.json").write_text(json.dumps(plan, indent=2))
    print(" ", plan.get("summary", ""))
    for f in plan["fixes"]:
        print("  director fix:", f)
    log = []
    accepted = {}
    for seg in segments:
        if seg not in plan["segments"] or seg not in backends:
            continue
        brief = plan["segments"][seg]
        sp = Specialist(seg, backends[seg], a.model)
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
                  f"judge {res.get('judge', {}).get('overall', '-')}", flush=True)
            if res["pass"]:
                break
            print("   ", res["evidence"].splitlines()[-1][:200], flush=True)
            if rnd < a.rounds - 1:
                code, prompt = sp.revise(brief, code, res["evidence"])
        free_model(sp)
        if res and res["pass"]:
            dest = GAME / "segments" / seg / "generated"
            dest.mkdir(parents=True, exist_ok=True)
            shutil.copy(res["path"], dest / f"{out.name}.gd")
            accepted[seg] = f"res://segments/{seg}/generated/{out.name}.gd"
    write_jsonl(out / "log.jsonl", log)
    swap = ";".join(f"{s}:{p}" for s, p in accepted.items())
    report = {"scene_brief": a.scene_brief, "world": plan["world"], "accepted": accepted,
              "unresolved": [s for s in segments if s not in accepted],
              "play": f"#world={plan['world']}" + (f"&swap={swap}" if swap else "")}
    if a.composite and accepted:
        spec = SEGMENTS["vegetation"]
        script = spec.get("script_by_world", {}).get(plan["world"], spec["script"])
        try:
            report["composite_frames"] = capture(plan["world"], swap, out / "composite", spec["shots"], script)["frames"]
        except Exception as e:
            report["composite_error"] = str(e)[:300]
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
