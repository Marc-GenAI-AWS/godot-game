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
TITLES = {"scene-beach-tropical-v2": "Beach · tropical afternoon",
          "scene-street-dusk-v3": "Street · dusk",
          "scene-street-overcast-v2": "Street · overcast morning"}

HEAD = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Scene Studio · Scenes built by specialist models</title>
<style>
body {{ margin: 0; font-family: 'Segoe UI', 'Noto Sans', Arial, sans-serif; color: #eaf2ff;
       background: linear-gradient(180deg, #0d2f6b 0%, #2f7fd6 55%, #b39a70 100%); min-height: 100vh; }}
main {{ max-width: 68rem; margin: 0 auto; padding: 3.5rem 1.5rem 4rem; }}
h1 {{ letter-spacing: 0.06em; margin: 0 0 0.6rem; font-size: 2rem; }}
p.lead {{ color: #dce9ff; margin-top: 0; line-height: 1.6; max-width: 52rem; }}
.how {{ background: rgba(6, 30, 70, 0.45); border-radius: 1rem; padding: 1.2rem 1.5rem; margin: 1.8rem 0 2.4rem; }}
.how h2 {{ margin: 0 0 0.8rem; font-size: 1rem; letter-spacing: 0.1em; text-transform: uppercase; color: #ffe9b3; }}
.steps {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(13rem, 1fr)); gap: 1rem; margin: 0; padding: 0; list-style: none; }}
.steps li {{ background: rgba(255,255,255,0.06); border-radius: 0.7rem; padding: 0.8rem 0.9rem; font-size: 0.88rem; line-height: 1.45; }}
.steps b {{ display: block; color: #ffe9b3; font-size: 0.78rem; letter-spacing: 0.08em; text-transform: uppercase; margin-bottom: 0.3rem; }}
.models {{ margin-top: 1rem; font-size: 0.85rem; color: #cfe2ff; line-height: 1.6; }}
.scene {{ background: rgba(6, 30, 70, 0.5); border-radius: 1rem; padding: 1.3rem 1.4rem 1.5rem; margin-bottom: 1.6rem;
          box-shadow: 0 0.8rem 2rem rgba(0,0,0,0.28); }}
.scene h2 {{ margin: 0 0 0.3rem; font-size: 1.25rem; }}
.brief {{ color: #dce9ff; font-style: italic; margin: 0 0 0.9rem; line-height: 1.5; }}
.shots {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 0.4rem; margin-bottom: 0.9rem; }}
.shots img {{ width: 100%; border-radius: 0.5rem; display: block; }}
.by {{ font-size: 0.85rem; color: #cfe2ff; margin: 0 0 1rem; }}
.play {{ display: inline-block; background: #ffd479; color: #10305f; font-weight: 600; text-decoration: none;
         padding: 0.55rem 1.1rem; border-radius: 0.6rem; font-size: 0.92rem; }}
.play:hover {{ background: #ffe4a8; }}
footer {{ margin-top: 2.5rem; font-size: 0.82rem; color: rgba(255,255,255,0.75); }}
a.back, footer a {{ color: #fff; }}
</style>
</head>
<body>
<main>
<p><a class="back" href="../">&larr; Scene Studio</a></p>
<h1>SCENES BUILT BY SPECIALIST MODELS</h1>
<p class="lead">Every scene below started as the one line of description printed under its title. Small
fine-tuned models wrote the game code for it - the terrain, the planting, the furniture, the sky - and a
verifier decided what was good enough to keep. Click through to walk around inside any of them.</p>

<div class="how">
  <h2>How these were made</h2>
  <ol class="steps">
    <li><b>1 · Director</b>Claude turns the one-line description into a precise brief for each part of the scene, agreeing on time of day, palette and mood.</li>
    <li><b>2 · Specialists</b>One small fine-tuned model per part writes Godot 4 GDScript from its brief. Each was trained only on its own segment.</li>
    <li><b>3 · Verifier</b>Every layer is loaded into the running game, captured from fixed camera angles and judged against the brief by Claude.</li>
    <li><b>4 · Composite</b>The assembled scene is then judged as a whole, and anything it blames goes back to that specialist to try again.</li>
    <li><b>5 · Publish</b>What the verifier accepts is installed into the Godot project and exported to the web build you are playing.</li>
  </ol>
  <p class="models"><b>The models:</b> each specialist is a LoRA fine-tune of Qwen2.5-Coder - 3B for sky, ground and
  vegetation, 7B for props - trained on layers written by a teacher model and filtered by the same verifier that
  grades them here. They run locally on one machine; the director and the judges are Claude on Bedrock.</p>
</div>
"""

FOOT = """<footer>Source: <a href="https://github.com/mlobree/godot-game">github.com/mlobree/godot-game</a> ·
Built with Godot 4 · Frames are the verifier's own captures of the assembled scene.</footer>
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
    segs = sorted(rep["accepted"])
    by = ", ".join(f"{s} ({MODEL_OF.get(s, 'specialist')})" for s in segs)
    shots = "".join(f'<img src="{n}" alt="{run} view {i + 1}">' for i, n in enumerate(names))
    title = TITLES.get(run, run.replace("scene-", "").replace("-v2", "").replace("-", " ").title())
    return (f'<div class="scene">\n  <h2>{title}</h2>\n'
            f'  <p class="brief">&ldquo;{rep["scene_brief"]}&rdquo;</p>\n'
            f'  <div class="shots">{shots}</div>\n'
            f'  <p class="by">Written by the specialists: {by}.</p>\n'
            f'  <a class="play" href="../play/{rep["play"]}">Play this scene</a>\n</div>\n')


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
