# 4. Publishing

The site is `docs/` on the `main` branch of
[Marc-GenAI-AWS/godot-game](https://github.com/Marc-GenAI-AWS/godot-game),
served at <https://marc-genai-aws.github.io/godot-game/>. There is no build
step and no CI: what is in `docs/` is what is live, a minute after you push.

```
docs/
  index.html              landing page
  play/                   the Godot web export (index.html/.js/.wasm/.pck)
  specialist-scenes/      the gallery: the playable game + the eight scenes
  specialist-skies/       an older per-sky gallery
  assets/gallery.css      shared styling, and game-menu.jpg (the hero shot)
  beach/                  redirect for an old URL
```

## Publish a change to the game

Run `tools/selftest.sh` first. Everything on this page puts something in front of the public,
and the suite takes about a minute.

```bash
godot --headless --path game --export-release Web ../docs/play/index.html
git add docs/play && git commit && git push
```

Run it from the repo root with an **absolute or `../`-relative** target: a
plain relative path resolves against `game/` and fails. The export preset
excludes `segments/*/candidates/*` (~3,600 verifier scripts, which is the
difference between a 34 MB and a 22 MB `.pck`), so anything a gallery link
loads must live outside `candidates/`.

The export is GL Compatibility and single-threaded on purpose — that is what
lets it run on Pages without cross-origin isolation headers.

## Rebuild the gallery

```bash
pipeline/.venv/bin/python pipeline/build_gallery_pages.py \
  --scenes v4-beach-noon v4-beach-dawn v4-beach-golden v4-beach-overcast \
           v4-street-morning v4-street-dusk v4-street-overcast v4-street-hazy \
  --out docs/specialist-scenes
```

It reads each run's `report.json` and `plan.json` from `pipeline/runs/`, copies
three frames per scene, quotes the brief each model was actually given, and
regenerates the pipeline diagram from the `LANES` table at the top of the
script. Editing the diagram means editing that table, not SVG.

It deletes `*.jpg` in the output directory first, so **do not keep a
hand-made image there** — the hero screenshot lives in `docs/assets/`
for exactly this reason.

### The hero screenshot

The shot at the top of the gallery shows the in-game menu open. A screen grab
cannot get it: on the desktop a Godot `PopupMenu` is its own OS window. So the
game takes it itself —

```bash
godot --path game --resolution 1280x720 -- --world=beach --menushot=/tmp/menu.png
```

`--menushot` switches the viewport to embedded sub-windows (what the web build
does anyway), opens the menu and a submenu, and saves the framebuffer.

## What the page says, and why

Marc's standing direction: the page shows **what the models built**, with the
models and the loop explained at the top. No rejected attempts, no judge
scores, no comparison against the hand-built scene. Each card quotes the brief
its layers were written from, so the caption always matches the picture, and
names the model size that wrote each layer.

## The two repositories

| Repo | Role |
|---|---|
| `Marc-GenAI-AWS/godot-game` | canonical; the site is published from here (git remote `origin`) |
| `mlobree/godot-game` | Marc's personal account; keeps the history, its five pages now redirect (remote `personal`) |

The redirect stubs were written by `tools/redirect_old_pages.py` — they copy
`location.hash` across, because the play links carry the scene in the fragment
and a plain meta refresh would drop it.

`gh`'s git credential helper only serves the **active** account, so a push
fails with 403 if you are switched to the other one:
`gh auth switch --user Marc-GenAI-AWS`.
