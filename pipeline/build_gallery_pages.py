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
# titled by what the models built and you can see, not by the weather in the original one-liner
TITLES = {"scene-beach-tropical-v2": "Beach &middot; golden sand, fan palms and loungers",
          "scene-street-dusk-v3": "Street &middot; dry lawns and kerbside lamps",
          "scene-street-overcast-v2": "Street &middot; fresh asphalt, palms and power poles"}

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
  <ol class="steps">
    <li><b><span class="n">1</span>Director</b>Claude turns one line of description into a precise brief for each part of the scene, agreeing on time of day, palette and mood.</li>
    <li><b><span class="n">2</span>Specialists</b>One small fine-tuned model per part writes Godot&nbsp;4 GDScript from its brief. Each is trained on its own segment only.</li>
    <li><b><span class="n">3</span>Verifier</b>Every layer is loaded into the running game, captured from fixed camera angles and judged against the brief.</li>
    <li><b><span class="n">4</span>Composite</b>The assembled scene is judged as a whole; whatever it blames goes back to that specialist to try again.</li>
    <li><b><span class="n">5</span>Publish</b>What the verifier accepts is installed in the project and exported to the web build you are playing.</li>
  </ol>
  <p class="models"><strong>The models.</strong> Every specialist is a LoRA fine-tune of Qwen2.5-Coder &mdash; 3B for
  sky, ground and vegetation, 7B for props &mdash; trained on layers written by a teacher model and filtered by the
  same verifier that grades them here. They run locally on a single machine; the director and the judges are Claude.</p>
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
    html = HEAD + "".join(card(s, out) for s in a.scenes) + FOOT
    (out / "index.html").write_text(html)
    print(f"wrote {out / 'index.html'} with {len(a.scenes)} scenes")


if __name__ == "__main__":
    main()
