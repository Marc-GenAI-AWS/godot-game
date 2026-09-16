"""Rebuild the public gallery from director runs: what the models built, nothing else.

    pipeline/.venv/bin/python pipeline/build_gallery_pages.py \
        --scenes scene-beach-tropical-v2 scene-street-overcast-v2 --out ../docs/specialist-scenes

Marc, 2026-09-15: the page should show the scenes the models produced and explain the
models and the loop at the top - no rejected attempts, no judge scores, no comparison
against the shipped scene. Each card keeps a plain credit line naming the segments the
specialists wrote, so the page never implies more than the models actually made.
"""
import argparse
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RUNS = ROOT / "runs"

MODEL_OF = {"sky": "Qwen2.5-Coder-3B", "ground": "Qwen2.5-Coder-3B", "vegetation": "Qwen2.5-Coder-3B",
            "props": "Qwen2.5-Coder-7B", "water": "Qwen2.5-Coder-3B"}
# titled by what the models built and you can see in the frames
TITLES = {"v4-beach-noon": "Beach &middot; clear tropical noon",
          "v4-beach-dawn": "Beach &middot; first light on a quiet shore",
          "v4-beach-golden": "Beach &middot; golden hour, packed with loungers",
          "v4-beach-overcast": "Beach &middot; overcast, grey volcanic sand",
          "v4-street-morning": "Street &middot; bright morning, fresh tarmac",
          "v4-street-dusk": "Street &middot; dusk, dry lawns and power poles",
          "v4-street-overcast": "Street &middot; overcast, clipped hedges",
          "v4-street-hazy": "Street &middot; hazy afternoon, double yellow lines"}

# Two lanes: how a specialist is made, and how a scene is made with it. Drawn from this table rather
# than hand-written markup so the wording stays easy to edit.
LANES = [
    ("Making a specialist", "once per segment", [
        ("Briefs", ["hundreds of them:", "time of day, weather,", "palette, density"]),
        ("Teacher", ["a large model writes", "two candidate layers", "for each brief"]),
        ("Verifier", ["renders each layer", "in the game and", "judges it"]),
        ("Dataset", ["only the layers", "that passed become", "training examples"]),
        ("Fine-tune", ["LoRA on", "Qwen2.5-Coder", "3B or 7B"]),
        ("Specialist", ["one small model", "that writes only", "this one layer"]),
    ]),
    ("Making a scene", "every time", [
        ("One line", ['"a lush tropical', 'afternoon on the', 'beach..."']),
        ("Director", ["a local 8B turns it", "into a precise brief", "per segment"]),
        ("Specialists", ["one per layer writes", "Godot code: sky,", "ground, plants, props"]),
        ("Verifier", ["renders, captures,", "judges against", "the brief"]),
        ("Composite", ["judges the whole", "assembled scene,", "names what is wrong"]),
        ("Playable", ["accepted layers ship", "into the web build", "you can walk around"]),
    ]),
]
BOX_W, BOX_H, GAP, LANE_H = 186, 104, 40, 250


def diagram_svg() -> str:
    w = 28 * 2 + BOX_W * 6 + GAP * 5
    h = 66 + LANE_H * len(LANES)
    out = [f'<svg class="flow" viewBox="0 0 {w} {h}" role="img" aria-label="How the models and the scenes are made">',
           '<defs><marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto">'
           '<path d="M0 0L10 5L0 10z" fill="currentColor"/></marker></defs>']
    for li, (title, cadence, boxes) in enumerate(LANES):
        top = 46 + li * LANE_H
        out.append(f'<text class="lane" x="28" y="{top - 14}">{title} <tspan class="cadence">&mdash; {cadence}</tspan></text>')
        for bi, (name, lines) in enumerate(boxes):
            x = 28 + bi * (BOX_W + GAP)
            out.append(f'<rect class="box" x="{x}" y="{top}" width="{BOX_W}" height="{BOX_H}" rx="10"/>')
            out.append(f'<text class="name" x="{x + 14}" y="{top + 28}">{name}</text>')
            for i, line in enumerate(lines):
                out.append(f'<text class="small" x="{x + 14}" y="{top + 52 + i * 17}">{line}</text>')
            if bi < len(boxes) - 1:
                x1, x2 = x + BOX_W + 6, x + BOX_W + GAP - 8
                out.append(f'<line class="arrow" x1="{x1}" y1="{top + BOX_H / 2}" x2="{x2}" y2="{top + BOX_H / 2}" marker-end="url(#ar)"/>')
        if li == 1:      # the loop: evidence and blame go back to the specialists
            sx = 28 + 3 * (BOX_W + GAP) + BOX_W / 2          # verifier
            cx = 28 + 4 * (BOX_W + GAP) + BOX_W / 2          # composite
            tx = 28 + 2 * (BOX_W + GAP) + BOX_W / 2          # specialists
            for src, label, drop in ((sx, "evidence &rarr; revise", 28), (cx, "blame &rarr; revise", 58)):
                y = top + BOX_H + drop
                out.append(f'<path class="feedback" d="M{src} {top + BOX_H + 2} V{y} H{tx} V{top + BOX_H + 6}" marker-end="url(#ar)"/>')
                out.append(f'<text class="fb" x="{(src + tx) / 2}" y="{y - 5}" text-anchor="middle">{label}</text>')
    out.append('<text class="foot" x="28" y="' + str(h - 10) + '">The same verifier that filtered the training data decides what ships &mdash; '
               'small models write, a judge accepts.</text>')
    out.append("</svg>")
    return "\n".join(out)


HEAD = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Scenes built by specialist models · Scene Studio</title>
<meta name="description" content="Playable Godot scenes written by small fine-tuned models: a director turns one line into per-segment briefs, specialists write the code, a verifier decides what ships.">
<link rel="stylesheet" href="../assets/gallery.css">
</head>
<body>
<main>
<a class="nav" href="../">&larr; Scene Studio</a>

<p class="eyebrow">Specialist models</p>
<h1>Playable scenes, written by small fine-tuned models</h1>
<p class="lead">Each scene below started as a single line of description. A director split that line into a
brief for every part of the scene, small fine-tuned models wrote the Godot code from those briefs, and a
verifier decided what was good enough to keep. Open any of them and walk around.</p>

<section class="how">
  <h2>How they were made</h2>
  __DIAGRAM__
  <p class="models"><strong>The models.</strong> Every specialist is a LoRA fine-tune of Qwen2.5-Coder &mdash; 3B for
  sky, ground and vegetation, 7B for props &mdash; trained on layers written by a teacher model and filtered by the
  same verifier that grades them here. The director that splits the description into per-part briefs is a fine-tuned
  Qwen3-8B, trained the same way. Every model that plans or writes a scene runs locally on one machine; Claude is
  only the judge that decides what is good enough to keep.</p>
</section>

<div class="scenes">
"""

FOOT = """</div>
<footer>Frames are the verifier\u2019s own captures of the assembled scene &middot;
Built with Godot&nbsp;4 &middot; <a href="https://github.com/mlobree/godot-game">github.com/mlobree/godot-game</a></footer>
</main>
</body>
</html>
"""


def card(run: str, out: Path) -> str:
    rep = json.loads((RUNS / run / "report.json").read_text())
    frames = [Path(p) for p in rep.get("composite_frames", [])]
    picks = [frames[0], frames[1], frames[3]] if len(frames) >= 4 else frames[:3]
    names = []
    for i, src in enumerate(picks):
        dest = out / f"{run}-{'abc'[i]}.jpg"
        from PIL import Image
        Image.open(src).convert("RGB").save(dest, quality=88)
        names.append(dest.name)
    title = TITLES.get(run, run.replace("scene-", "").replace("-v2", "").replace("-", " ").title())
    # one large frame beside two stacked ones reads as a scene rather than a filmstrip
    hero, rest = names[0], names[1:]
    stack = "".join(f'<img src="{n}" alt="{title}, view {i + 2}" loading="lazy">' for i, n in enumerate(rest))
    # quote the brief each model was actually given, so the caption always matches the picture
    plan = json.loads((RUNS / run / "plan.json").read_text())
    rows = ""
    for seg in sorted(rep["accepted"]):
        text = (plan.get("segments", {}).get(seg) or {}).get("text", "")
        size = MODEL_OF.get(seg, "specialist").split("-")[-1]
        rows += (f'      <div class="seg"><span class="seg-name">{seg}<span class="size">{size}</span></span>'
                 f'<span class="seg-brief">{text}</span></div>\n')
    return (f'<article class="scene">\n'
            f'  <div class="shots"><img src="{hero}" alt="{title}" loading="lazy">'
            f'<div class="stack">{stack}</div></div>\n'
            f'  <div class="scene-body">\n    <h2>{title}</h2>\n'
            f'    <p class="kicker">What the director asked each model for</p>\n'
            f'    <div class="segs">\n{rows}    </div>\n'
            f'    <div class="meta">\n'
            f'      <a class="play" href="../play/{rep["play"]}">Play this scene'
            f'<svg viewBox="0 0 10 10" fill="currentColor" aria-hidden="true"><path d="M1 0l8 5-8 5z"/></svg></a>\n'
            f'    </div>\n  </div>\n</article>\n')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenes", nargs="+", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    out = Path(a.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.jpg"):     # the old page's rejected / shipped thumbnails
        old.unlink()
    html = HEAD.replace("__DIAGRAM__", diagram_svg()) + "".join(card(s, out) for s in a.scenes) + FOOT
    (out / "index.html").write_text(html)
    print(f"wrote {out / 'index.html'} with {len(a.scenes)} scenes")


if __name__ == "__main__":
    main()
