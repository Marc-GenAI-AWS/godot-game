# Boulder Hill

A small Godot 4 scene: a large boulder rolls down a grassy hillside, kicking up
dust, with a chase camera following it into the valley. Click, tap, or press
R / Space to roll it again. It restarts on its own once the rock comes to rest.

**Play it in the browser:** the web build in `docs/` is served by GitHub Pages.

## Layout

- `boulder/` – the Godot project. Everything (terrain, trees, rock, camera,
  particles, lighting) is generated in `main.gd`, so the scene file is tiny.
- `docs/` – the exported Web build (HTML + JS + WASM + PCK). Regenerate with:

  ```bash
  cd boulder
  godot --headless --export-release Web ../docs/index.html
  ```

- `shots/` – a small DevTools-protocol script that drives headless Chromium to
  screenshot the web build at fixed times, used to check renders without a GUI.

Built with Godot 4.7.2 using the GL Compatibility renderer and a
single-threaded web export, so it runs on GitHub Pages without special headers.
