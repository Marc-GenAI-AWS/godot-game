"""Re-capture the gallery's scene frames without re-running the director.

    DISPLAY=:0 pipeline/.venv/bin/python pipeline/refresh_gallery_frames.py \
        --scenes v4-beach-noon v4-beach-dawn ... [--dry-run]

A published frame is a photograph of the game, so it goes stale whenever the game changes - a
new outfit, a repainted texture, a fixed layer. Re-running the director would write new scenes
(and cost judge calls); this re-photographs the scenes already accepted, from their report.json:
the same world, the same swapped-in layers, the same two camera recipes and shot times the
composite verifier used, overwriting the frames in place.

Nothing is judged and nothing is generated, so it costs only GPU time - about 25 seconds a view.
Afterwards run build_gallery_pages.py to copy the new frames into docs/.
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import GODOT, RUNS, SEGMENTS  # noqa: E402


def recipes_for(world: str) -> list:
    out = []
    for r in SEGMENTS["composite"]["recipes"]:
        script = r.get("script_by_world", {}).get(world, r["script"])
        out.append({"shots": r["shots"], "script": script})
    return out


def capture(scene: str, dry: bool) -> bool:
    report = RUNS / scene / "report.json"
    if not report.exists():
        print(f"{scene}: no report.json, skipped")
        return False
    rep = json.loads(report.read_text())
    world = rep.get("world", "beach")
    # the play link already carries exactly the layers this scene was accepted with
    swap = rep["play"].split("swap=", 1)[1] if "swap=" in rep["play"] else ""
    ok = True
    for i, r in enumerate(recipes_for(world)):
        out = RUNS / scene / "composite" / "round0" / f"view{i}"
        cmd = [str(GODOT), "--path", "game", "--resolution", "1280x720", "--",
               f"--world={world}", f"--capture={out}", f"--shots={r['shots']}",
               f"--script={r['script']}"]
        if swap:
            cmd.append(f"--swap={swap}")
        print(f"{scene} view{i} -> {out}")
        if dry:
            continue
        # Godot chdirs into the project, so --capture must be absolute (it is: RUNS is absolute)
        p = subprocess.run(cmd, cwd=RUNS.parent.parent, capture_output=True, text=True, timeout=300)
        shots = sorted(out.glob("*.png"))
        if len(shots) < len(r["shots"].split(",")):
            print(f"  only {len(shots)} frames: {p.stdout[-300:]}")
            ok = False
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenes", nargs="+", required=True)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    done = 0
    for scene in a.scenes:
        if capture(scene, a.dry_run):
            done += 1
    print(f"\nre-photographed {done}/{len(a.scenes)} scenes; now run build_gallery_pages.py")


if __name__ == "__main__":
    main()
