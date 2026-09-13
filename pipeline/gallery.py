"""Contact sheets comparing several evaluation runs per held-out brief.

    pipeline/.venv/bin/python pipeline/gallery.py --briefs pipeline/runs/sky12/sft/heldout_briefs.jsonl \
        --runs 7B=eval-sky-7b-v2 3B=eval-sky-3b 1.5B=eval-sky-1p5b --out pipeline/runs/bakeoff_gallery

One row per brief (text on the left), one column per run: the tilted-up frame,
pass/fail, judge score, checks score and the judge's weakest attribute.
"""
import argparse
import json
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent


def wrap(text, width=38):
    words, lines, cur = text.split(), [], ""
    for w in words:
        if len(cur) + len(w) + 1 > width:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w).strip()
    return lines + [cur]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--briefs", required=True)
    ap.add_argument("--runs", nargs="+", required=True, help="label=run_dir_name under pipeline/runs")
    ap.add_argument("--out", required=True)
    ap.add_argument("--per-sheet", type=int, default=10)
    ap.add_argument("--view", default="_6s.png", help="which capture to show")
    a = ap.parse_args()
    runs = [r.split("=", 1) for r in a.runs]
    briefs = [json.loads(l) for l in open(a.briefs)]
    briefs.sort(key=lambda b: (b["time_of_day"], b["weather"]))
    res = {}
    for tag, run in runs:
        for l in open(ROOT / "runs" / run / "verified.jsonl"):
            r = json.loads(l)
            res[(tag, r["brief_id"])] = r
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
        bold = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 15)
    except Exception:
        font = bold = ImageFont.load_default()
    W, H, LW = 400, 225, 330
    os.makedirs(a.out, exist_ok=True)
    for si in range(0, len(briefs), a.per_sheet):
        chunk = briefs[si:si + a.per_sheet]
        sheet = Image.new("RGB", (LW + len(runs) * (W + 10) + 10, 60 + len(chunk) * (H + 42)), (245, 245, 245))
        d = ImageDraw.Draw(sheet)
        d.text((10, 15), "One-shot output per run on the held-out briefs", font=bold, fill=(20, 20, 20))
        for ci, (tag, _) in enumerate(runs):
            d.text((LW + 10 + ci * (W + 10), 38), tag, font=bold, fill=(20, 20, 20))
        for ri, b in enumerate(chunk):
            y = 60 + ri * (H + 42)
            lines = (wrap(f"{b['time_of_day']}, {b['weather']}")
                     + wrap(f"sun {b['sun_elevation_deg']:.0f} deg at {b['sun_azimuth_deg']} deg, cover {b['cloud_cover']:.2f}, haze {b['haze']:.2f}")
                     + wrap(", ".join(b["palette_words"]) + f", {b['mood']} ({b['world']})"))
            for li, line in enumerate(lines[:9]):
                d.text((10, y + 4 + li * 19), line, font=bold if li == 0 else font, fill=(30, 30, 30))
            for ci, (tag, run) in enumerate(runs):
                x = LW + 10 + ci * (W + 10)
                r = res.get((tag, b["id"]))
                frames = (r.get("frames") or []) if r else []
                frame = next((f for f in frames if f.endswith(a.view)), frames[0] if frames else None)
                if frame and os.path.exists(frame):
                    sheet.paste(Image.open(frame).convert("RGB").resize((W, H), Image.LANCZOS), (x, y))
                else:
                    d.rectangle([x, y, x + W, y + H], fill=(60, 60, 60))
                    d.text((x + 12, y + H // 2 - 8), "no render (gate failure)", font=font, fill=(230, 230, 230))
                if r:
                    j = r.get("judge", {})
                    ok = r["pass"]
                    d.rectangle([x, y + H, x + W, y + H + 22], fill=(200, 235, 200) if ok else (240, 205, 205))
                    d.text((x + 6, y + H + 3), f"{'PASS' if ok else 'fail'}  judge {j.get('overall', '-')}/10  checks {r['checks'].get('score', 0):.2f}", font=bold, fill=(20, 20, 20))
                    if j.get("attributes"):
                        at = j["attributes"]
                        k = min(at, key=lambda k: at[k].get("score", 10))
                        d.text((x + 6, y + H + 25), f"weakest: {k} {at[k].get('score')} - {at[k].get('evidence', '')}"[:52], font=font, fill=(70, 70, 70))
        out = Path(a.out) / f"sheet_{si // a.per_sheet + 1}.png"
        sheet.save(out)
        print(out, sheet.size)


if __name__ == "__main__":
    main()
