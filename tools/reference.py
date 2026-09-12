#!/usr/bin/env python3
"""Turn a reference clip into study material: a contact sheet, evenly spaced
full frames, and optional region crops, under examples/<clip-slug>/.

    python3 tools/reference.py "examples/man walking street.mp4"
    python3 tools/reference.py examples/*.mp4            # all clips
    python3 tools/reference.py clip.mp4 --crop sky=0,0,1,0.35 --crop road=0,0.5,1,1

Crops are fractions x0,y0,x1,y1 of the frame. A summary line per clip goes to
examples/index.json so the scene families can be tagged by hand.
"""
import argparse, json, os, re, subprocess, sys

def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=width,height",
                          "-of", "json", path], capture_output=True, text=True).stdout
    d = json.loads(out)
    st = [s for s in d.get("streams", []) if "width" in s][0]
    return float(d["format"]["duration"]), int(st["width"]), int(st["height"])

def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", os.path.splitext(os.path.basename(name))[0].lower()).strip("-")

def run(cmd):
    subprocess.run(cmd, check=True, capture_output=True)

def process(path, crops, frames, sheet_cols, sheet_rows):
    dur, w, h = probe(path)
    out = os.path.join("examples", slug(path))
    os.makedirs(os.path.join(out, "frames"), exist_ok=True)
    n = sheet_cols * sheet_rows
    run(["ffmpeg", "-y", "-v", "error", "-i", path, "-vf", f"fps={n}/{dur},scale=426:-1,tile={sheet_cols}x{sheet_rows}", "-frames:v", "1", os.path.join(out, "sheet.png")])
    run(["ffmpeg", "-y", "-v", "error", "-i", path, "-vf", f"fps={frames}/{dur},scale=1280:-1", os.path.join(out, "frames", "f_%02d.png")])
    for name, (x0, y0, x1, y1) in crops.items():
        cw, ch = int((x1 - x0) * w), int((y1 - y0) * h)
        run(["ffmpeg", "-y", "-v", "error", "-ss", str(dur * 0.5), "-i", path, "-frames:v", "1",
             "-vf", f"crop={cw}:{ch}:{int(x0 * w)}:{int(y0 * h)},scale={min(1600, cw * 3)}:-1:flags=lanczos", os.path.join(out, f"crop_{name}.png")])
    entry = {"file": path, "slug": slug(path), "duration_s": round(dur, 2), "size": [w, h], "frames": frames, "family": "", "notes": ""}
    idx_path = os.path.join("examples", "index.json")
    idx = json.load(open(idx_path)) if os.path.exists(idx_path) else {}
    idx.setdefault(entry["slug"], {}).update({k: v for k, v in entry.items() if k not in ("family", "notes") or k not in idx.get(entry["slug"], {})})
    json.dump(idx, open(idx_path, "w"), indent=2)
    print(f"{entry['slug']}: {dur:.1f}s {w}x{h} -> {out}/")

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("clips", nargs="+")
    ap.add_argument("--frames", type=int, default=6)
    ap.add_argument("--sheet", default="4x3")
    ap.add_argument("--crop", action="append", default=[], help="name=x0,y0,x1,y1 (fractions)")
    a = ap.parse_args()
    crops = {}
    for c in a.crop:
        name, vals = c.split("=")
        crops[name] = tuple(float(v) for v in vals.split(","))
    cols, rows = (int(v) for v in a.sheet.split("x"))
    for clip in a.clips:
        process(clip, crops, a.frames, cols, rows)
