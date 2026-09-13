"""Brief sampler: structured, diverse briefs per segment.

    python3 pipeline/briefs.py sky --n 24 --seed 1 --out pipeline/runs/sky1/briefs.jsonl

Diversity is the biggest lever for the specialist, so the sampler covers the
brief space evenly (time of day x weather) rather than sampling uniformly at
random, and then adds palette and mood words.
"""
import argparse
import itertools
import json
import random
from pathlib import Path

from common import CONTRACT_VERSION, write_jsonl

TIMES = {
    "dawn": {"elev": (3, 12), "words": ["pink-gold horizon", "cool violet zenith", "long soft shadows"]},
    "morning": {"elev": (25, 40), "words": ["clean light", "pale blue", "crisp shadows"]},
    "noon": {"elev": (55, 75), "words": ["hard white sun", "deep saturated blue zenith", "short shadows"]},
    "afternoon": {"elev": (30, 45), "words": ["warm neutral light", "slightly hazy horizon"]},
    "golden hour": {"elev": (6, 15), "words": ["orange sun", "amber highlights", "very long shadows", "warm haze"]},
    "dusk": {"elev": (-2, 4), "words": ["magenta and orange band at the horizon", "indigo zenith", "sun just at the horizon"]},
    "night": {"elev": (-20, -8), "words": ["moonlit", "deep navy zenith", "cool blue fill", "faint horizon glow"]},
}
WEATHER = {
    "clear": {"cover": (0.0, 0.15), "haze": (0.05, 0.25)},
    "scattered clouds": {"cover": (0.25, 0.45), "haze": (0.1, 0.35)},
    "broken clouds": {"cover": (0.5, 0.7), "haze": (0.2, 0.5)},
    "overcast": {"cover": (0.85, 1.0), "haze": (0.4, 0.8)},
    "hazy": {"cover": (0.05, 0.3), "haze": (0.7, 1.0)},
}
MOODS = ["postcard", "cinematic", "documentary", "dreamy", "gritty", "serene", "stormy-light", "tropical"]
WORLDS = ["beach", "street"]


def sample_sky(n: int, seed: int):
    rng = random.Random(seed)
    combos = list(itertools.product(TIMES.keys(), WEATHER.keys()))
    rng.shuffle(combos)
    out = []
    for i in range(n):
        tod, wx = combos[i % len(combos)]
        t, w = TIMES[tod], WEATHER[wx]
        elev = round(rng.uniform(*t["elev"]), 1)
        cover = round(rng.uniform(*w["cover"]), 2)
        haze = round(rng.uniform(*w["haze"]), 2)
        azimuth = rng.choice([30, 60, 90, 120, 150, 210, 240, 270, 300, 330])
        world = rng.choice(WORLDS)
        words = rng.sample(t["words"], k=min(2, len(t["words"])))
        mood = rng.choice(MOODS)
        brief = {
            "id": f"sky-{seed:02d}-{i:03d}",
            "segment": "sky",
            "contract": CONTRACT_VERSION,
            "world": world,
            "time_of_day": tod,
            "weather": wx,
            "sun_elevation_deg": elev,
            "sun_azimuth_deg": azimuth,
            "cloud_cover": cover,
            "haze": haze,
            "wind_strength": round(rng.uniform(0.3, 2.0), 2),
            "palette_words": words,
            "mood": mood,
            "text": (f"A {mood} {tod} sky over the {world} scene, {wx}. Sun elevation {elev} degrees, "
                     f"azimuth {azimuth} degrees. Cloud cover {cover:.2f}, haze {haze:.2f}. "
                     f"Palette: {', '.join(words)}."),
        }
        out.append(brief)
    return out


SAMPLERS = {"sky": sample_sky}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("segment", choices=SAMPLERS.keys())
    ap.add_argument("--n", type=int, default=24)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    rows = SAMPLERS[a.segment](a.n, a.seed)
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    write_jsonl(a.out, rows)
    print(f"wrote {len(rows)} {a.segment} briefs to {a.out}")
    for r in rows[:3]:
        print(" ", r["text"])


if __name__ == "__main__":
    main()
