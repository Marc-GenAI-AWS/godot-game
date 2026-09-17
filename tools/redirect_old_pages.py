"""Replace the personal account's site with redirects to the work account's copy.

    python3 tools/redirect_old_pages.py --dry-run
    python3 tools/redirect_old_pages.py

Marc, 2026-09-16: the gallery now lives at Marc-GenAI-AWS/godot-game, next to the Recipes
repo. mlobree/godot-game keeps its history but stops serving the site, so every page it
still serves points at the new one - links already shared should land somewhere.

The stub is not just a meta refresh: the play links carry the scene in the URL fragment
("play/#world=beach&swap=..."), and a meta refresh drops it. The script copies location.hash
across, with the meta refresh as the fallback when JavaScript is off.

Writes through the contents API, so the personal repo does not need a checkout and the local
tree - which is the work account's copy now - is left alone.
"""
import argparse
import base64
import json
import subprocess

REPO = "mlobree/godot-game"
NEW = "https://marc-genai-aws.github.io/godot-game"
PAGES = {"docs/index.html": "", "docs/beach/index.html": "beach/",
         "docs/play/index.html": "play/", "docs/specialist-scenes/index.html": "specialist-scenes/",
         "docs/specialist-skies/index.html": "specialist-skies/"}

STUB = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Scene Studio has moved</title>
<link rel="canonical" href="{url}">
<meta http-equiv="refresh" content="0; url={url}">
<script>location.replace({url!r} + location.hash);</script>
<style>
  body {{ margin: 0; min-height: 100vh; display: grid; place-items: center;
         background: #0a0b0d; color: #edeef1; font: 16px/1.6 ui-sans-serif, "Segoe UI", Arial, sans-serif; }}
  p {{ max-width: 34rem; padding: 2rem; text-align: center; color: #9aa1ab; }}
  a {{ color: #e0a458; }}
</style>
</head>
<body>
<p>Scene Studio now lives at <a href="{url}">{shown}</a>.</p>
</body>
</html>
"""


def gh(*args: str) -> str:
    return subprocess.run(["gh", *args], capture_output=True, text=True, check=True).stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    who = gh("api", "user", "--jq", ".login").strip()
    if who != "mlobree":
        raise SystemExit(f"gh is acting as {who}; run 'gh auth switch --user mlobree' first")
    for path, tail in PAGES.items():
        url = f"{NEW}/{tail}"
        body = STUB.format(url=url, shown=url.replace("https://", ""))
        sha = json.loads(gh("api", f"repos/{REPO}/contents/{path}"))["sha"]
        if a.dry_run:
            print(f"would rewrite {path} -> {url}")
            continue
        gh("api", "-X", "PUT", f"repos/{REPO}/contents/{path}",
           "-f", f"message=Redirect {tail or 'the landing page'} to the copy on Marc-GenAI-AWS",
           "-f", f"content={base64.b64encode(body.encode()).decode()}", "-f", f"sha={sha}")
        print(f"rewrote {path} -> {url}")


if __name__ == "__main__":
    main()
