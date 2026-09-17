"""Generate segment briefs with a model instead of a hand-written sampler.

    PYTHONPATH=. .venv/bin/python brief_gen.py --segment characters --world beach --n 12 \
        --host http://192.168.4.29:8001/v1 --model qwen38-27b --out runs/charbriefs1

briefs.py samples from vocabularies written by hand, so its brief space is small and finite -
street ground is 324 combinations, and a 72-brief run mostly repeats what the specialist has
already seen. This asks a model for briefs instead, then checks every one against what the game
can actually build: a brief naming an outfit or hair style that does not exist is worse than a
dull one, because the specialist would be trained toward something unreachable.

Reported per batch: how many are implementable, how many are new, and which fields the model
reached for. The hand-written sampler is the baseline to beat on variety, not on validity.
"""
import argparse
import json
import re
import time
import urllib.request
from pathlib import Path

from briefs import (CHAR_BODY_TYPES, CHAR_DENSITY, CHAR_HAIR, CHAR_OUTFITS, CHAR_SPREAD,  # noqa: F401
                    characters_brief)
from common import write_jsonl

SYSTEM = """You invent briefs for one part of a procedural game scene. A brief is a short, concrete
instruction that a small code-writing model turns into a Godot layer. It describes intent and mix,
never code.

You are writing briefs for the CHARACTERS layer: the people in the scene. The layer does not model
bodies - it places and configures people from a fixed set of assets. So a brief can only vary who is
there and how they are arranged, and every value must come from these lists:

  density: {density}
  spread:  {spread}
  body types available: {bodies}
  hair (female): {hair_f}      hair (male): {hair_m}
  outfits ({world}, female): {outfit_f}
  outfits ({world}, male): {outfit_m}
  (write these in plain words - "a navy one-piece", "white tee over jeans" - never the asset id)
  skin tones: five fixed tints, from very fair to deep
  hair tints: five fixed tints, from black through brown to blonde

Clothing is the point of these briefs. "outfit_mix" is the field that matters most: name the actual
garments and colours from the list above and say how they are distributed. Be specific about
proportions and about what is absent.

  good: "black and navy one-pieces on most of the women, two floral bikinis, trunks nearly all blue"
  good: "white tees over jeans dominate, one red tee, no shorts at all"
  weak: "colourful swimwear"                      (names nothing)
  weak: "a mix of outfits"                        (says nothing)
  weak: "T_F_bikini_pink on half the women"       (asset ids belong in code, not a brief)

Write every brief the way you would say it to a person: "pink bikinis", not "T_F_bikini_pink".

Give every brief a different clothing story: one colour dominating, two colours clashing, a single
outfit repeated across the crowd, deliberately drab, one bright figure among muted ones, colours
split between the sexes. The other fields - body, hair, skin, spread - should support that story
rather than compete with it, and may be brief.

Do not invent garments, hairstyles, ages, props or activities the list cannot express: no children,
no hats, no sunglasses, no surfboards, no wetsuits, however good the idea. Only the listed outfits
exist.

Reply with a JSON array of {n} objects, no prose, each with exactly these keys:
  "density", "spread", "body_mix", "outfit_mix", "hair_mix", "skin_mix", "look"
"look" is two or three words for the mood, like "relaxed holiday" or "brisk off-season"."""


def ask(host: str, model: str, prompt: str, n: int, temperature: float, timeout: int = 900) -> str:
    body = {"model": model, "max_tokens": 200 * n + 400, "temperature": temperature,
            "chat_template_kwargs": {"enable_thinking": False},   # this family narrates otherwise
            "messages": [{"role": "system", "content": prompt},
                         {"role": "user", "content": f"Write {n} briefs. JSON array only."}]}
    req = urllib.request.Request(host.rstrip("/") + "/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)["choices"][0]["message"]["content"]


def parse_array(text: str) -> list:
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.S)
    m = re.search(r"\[.*\]", text, re.S)
    if not m:
        raise ValueError("no JSON array in the reply")
    return json.loads(m.group(0))


GARMENT_WORDS = {"bikini": "bikini", "onepiece": "one-piece", "trunks": "trunks",
                 "tee": "tee", "jeans": "jeans", "chinos": "chinos", "shorts": "shorts"}


def plain_words(text: str) -> str:
    """Turn any asset id that slipped through into the words a person would use:
    T_F_bikini_pink -> "pink bikini", T_M_tee_white_jeans -> "white tee with jeans"."""
    def one(m):
        parts = m.group(0).split("_")[2:]          # drop the T_F_ / T_M_ prefix
        garment = GARMENT_WORDS.get(parts[0], parts[0])
        rest = parts[1:]
        if garment == "tee" and rest and rest[-1] in ("jeans", "chinos", "shorts"):
            colour, bottom = " ".join(rest[:-1]), rest[-1]
            return f"{colour} tee with {bottom}".strip()
        return f"{' '.join(rest)} {garment}".strip()
    return re.sub(r"T_[FM]_[a-z_]+", one, text)


def check(raw: dict, world: str) -> list:
    """What makes a generated brief unusable: a value the game cannot build."""
    bad = []
    for k in ("density", "spread", "body_mix", "outfit_mix", "hair_mix", "skin_mix", "look"):
        if not str(raw.get(k, "")).strip():
            bad.append(f"missing {k}")
    if raw.get("density") and raw["density"] not in CHAR_DENSITY:
        bad.append(f"density {raw['density']!r} is not one of {CHAR_DENSITY}")
    if raw.get("spread") and raw["spread"] not in CHAR_SPREAD:
        bad.append(f"spread {raw['spread']!r} is not one of the listed spreads")
    # free-text mixes: reject only what the assets cannot express at all
    blob = " ".join(str(raw.get(k, "")) for k in ("body_mix", "outfit_mix", "hair_mix", "skin_mix", "look")).lower()
    for word, why in (("child", "no child bodies"), ("kid", "no child bodies"), ("toddler", "no child bodies"),
                      ("hat", "no hat assets"), ("cap", "no hat assets"), ("sunglass", "no eyewear assets"),
                      ("surfboard", "props layer, not characters"), ("dog", "no animal assets"),
                      ("wetsuit", "no wetsuit outfit"),
                      ("elderly", "one adult body per sex"), ("teen", "one adult body per sex")):
        if word in blob:
            bad.append(f"mentions {word!r}: {why}")
    # "uniform" is usually the adjective ("a uniform navy tone", "uniformly average build"), which is
    # perfectly buildable. Only the garment sense is a problem, and a plain substring match threw away
    # four good briefs before this was fixed.
    for m in re.finditer(r"\buniforms?\b", blob):
        prev = re.findall(r"[a-z]+", blob[:m.start()])[-1:]          # the word immediately before
        nxt = re.findall(r"[a-z]+", blob[m.end():])[:1]              # and immediately after
        garment_sense = (prev and prev[0] in {"school", "team", "staff", "work", "matching", "in"}) or \
                        (nxt and nxt[0] in {"shirt", "shirts", "top", "tops", "dress", "dresses", "jacket"})
        if garment_sense:
            bad.append("mentions a uniform as clothing: no uniform outfit exists")
            break
    for body in re.findall(r"\b(slim|average|tall|short|stocky|athletic|muscular|petite|heavy)\b", blob):
        if body not in CHAR_BODY_TYPES:
            bad.append(f"body type {body!r} does not exist (have: {CHAR_BODY_TYPES})")
    # clothing is the point: the outfit mix has to name real garments, not gesture at "colourful swimwear"
    garments = {"beach": ["bikini", "one-piece", "onepiece", "trunks", "swimsuit"],
                "street": ["tee", "t-shirt", "jeans", "chinos", "shorts"]}[world]
    colours = ["pink", "teal", "black", "floral", "red", "navy", "blue", "white", "green"]
    om = str(raw.get("outfit_mix", "")).lower()
    if not any(g in om for g in garments):
        bad.append(f"outfit_mix names no {world} garment (have: {garments})")
    elif not any(c in om for c in colours):
        bad.append("outfit_mix names no colour from the outfit list")
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--segment", default="characters", choices=["characters"])
    ap.add_argument("--world", default="beach", choices=["beach", "street"])
    ap.add_argument("--n", type=int, default=12, help="briefs per request")
    ap.add_argument("--batches", type=int, default=1)
    ap.add_argument("--temperature", type=float, default=0.95)
    ap.add_argument("--host", default="http://192.168.4.29:8001/v1")
    ap.add_argument("--model", default="qwen38-27b")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    prompt = SYSTEM.format(n=a.n, world=a.world, density=CHAR_DENSITY, spread=CHAR_SPREAD,
                           bodies=CHAR_BODY_TYPES, hair_f=CHAR_HAIR["F"], hair_m=CHAR_HAIR["M"],
                           outfit_f=CHAR_OUTFITS[a.world]["F"], outfit_m=CHAR_OUTFITS[a.world]["M"])
    kept, rejected, seen = [], [], set()
    for b in range(a.batches):
        t0 = time.time()
        try:
            raws = parse_array(ask(a.host, a.model, prompt, a.n, a.temperature))
        except Exception as e:
            print(f"batch {b + 1}: failed ({str(e)[:120]})"); continue
        print(f"batch {b + 1}: {len(raws)} briefs in {time.time() - t0:.0f}s")
        for i, raw in enumerate(raws):
            problems = check(raw, a.world)
            if problems:
                rejected.append({"raw": raw, "problems": problems})
                print(f"   reject: {'; '.join(problems)[:100]}")
                continue
            brief = characters_brief(f"char-{a.world[:2]}-{len(kept):03d}", a.world, raw["density"], raw["spread"],
                                     plain_words(raw["body_mix"]), plain_words(raw["outfit_mix"]),
                                     plain_words(raw["hair_mix"]), plain_words(raw["skin_mix"]), raw["look"])
            if brief["text"] in seen:
                rejected.append({"raw": raw, "problems": ["duplicate of an earlier brief"]}); continue
            seen.add(brief["text"])
            kept.append(brief)
            print(f"   ok: {brief['text'][:130]}")

    write_jsonl(out / "briefs.jsonl", kept)
    (out / "rejected.json").write_text(json.dumps(rejected, indent=1))
    total = len(kept) + len(rejected)
    print(f"\n{len(kept)}/{total} usable -> {out / 'briefs.jsonl'}")
    if rejected:
        why = {}
        for r in rejected:
            why[r["problems"][0].split(":")[0]] = why.get(r["problems"][0].split(":")[0], 0) + 1
        print("rejected because:", dict(sorted(why.items(), key=lambda kv: -kv[1])))
    if kept:
        for field in ("density", "spread", "look"):
            vals = {b[field] for b in kept}
            print(f"  distinct {field}: {len(vals)}")


if __name__ == "__main__":
    main()
