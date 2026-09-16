"""Whole-scene brief sampler: the one-line briefs a person would type at the director.

    python3 pipeline/scene_briefs.py --n 300 --seed 1 --out pipeline/runs/dir1/scene_briefs.jsonl

Each brief names a world, a time of day and weather, and mentions two or three
segments in ordinary words (never the trained vocabulary verbatim, so the
director has to do the translation it is being trained on). The fields the brief
was built from are kept alongside it as `intent`, which the director verifier
checks the plan against.
"""
import argparse
import random
from pathlib import Path

from common import write_jsonl

WORLDS = ["beach", "street"]

TIMES = {
    "dawn": ["just after sunrise", "at first light", "early, with the sun barely up"],
    "morning": ["mid-morning", "on a bright morning", "in the clean morning light"],
    "noon": ["at midday", "under a high noon sun", "in the middle of the day"],
    "afternoon": ["in the late afternoon", "on a lazy afternoon", "mid-afternoon"],
    "golden hour": ["in the golden hour", "with the sun low and amber", "late, everything gone gold"],
    "dusk": ["at dusk", "as the sun drops behind the horizon", "in the last light"],
    "night": ["at night", "well after dark", "under a moonlit sky"],
}
WEATHER = {
    "clear": ["a clear sky", "not a cloud anywhere", "clean blue overhead"],
    "scattered clouds": ["a few clouds drifting past", "scattered puffy clouds", "the odd cloud"],
    "broken clouds": ["broken cloud", "half the sky clouded over", "patchy cloud cover"],
    "overcast": ["a flat grey overcast", "a solid deck of cloud", "heavy grey cloud, sun hidden"],
    "hazy": ["a thick haze", "hazy, washed-out air", "a soft haze over everything"],
}

# Ordinary words for each segment, each paired with the trained value the director should choose for it
# (segment, field, value). Translating the left side into the right side is the director's whole job, so
# the grader can mark a plan without a GPU: the mentioned field must come back as exactly this value.
BEACH_GROUND = [
    ("pale coral sand", "ground", "tone", "pale white coral sand"),
    ("dark tan sand", "ground", "tone", "dark warm tan"),
    ("golden sand", "ground", "tone", "golden"),
    ("grey volcanic sand", "ground", "tone", "grey volcanic"),
    ("pinkish shell sand", "ground", "tone", "pinkish shell sand"),
    ("a wide wet band at the tide line with a mirror sheen", "ground", "wet_band", "wide wet band with a strong mirror sheet"),
    ("only a narrow strip of wet sand", "ground", "wet_band", "narrow wet band"),
    ("sand thick with shells and pebbles at the tide line", "ground", "shells", "shells and pebbles along the tide line"),
    ("a dense drift of shells", "ground", "shells", "dense shell drift"),
    ("smooth packed sand", "ground", "grain", "smooth packed sand"),
    ("coarse rippled sand", "ground", "grain", "coarse grain with ripples"),
]
STREET_GROUND = [
    ("fresh black tarmac", "ground", "tone", "fresh black asphalt"),
    ("worn grey asphalt", "ground", "tone", "worn grey asphalt"),
    ("sun-baked brownish road", "ground", "tone", "brownish sun-baked asphalt"),
    ("patched, faded road", "ground", "tone", "patched and faded asphalt"),
    ("a single dashed white line down the middle", "ground", "markings", "single dashed white centre line"),
    ("double yellow lines down the middle", "ground", "markings", "double yellow centre line and white edge lines"),
    ("no centre line, just white edges", "ground", "markings", "no centre line, white edge lines only"),
    ("red-painted kerbs by the crossing", "ground", "kerb", "red-painted kerbs by the crossing"),
    ("grey granite kerbs", "ground", "kerb", "granite grey kerbs"),
    ("cracked short sidewalk slabs", "ground", "sidewalk", "short sidewalk slabs with cracks"),
    ("long clean paving slabs", "ground", "sidewalk", "long clean slabs"),
    ("lush green lawns", "ground", "lawn", "lush green lawns"),
    ("dry yellowing lawns", "ground", "lawn", "dry yellow-green lawns"),
    ("dark lawns mown into stripes", "ground", "lawn", "dark mown lawns with stripes"),
]
BEACH_VEG = [
    ("tall fan palms and nothing else", "vegetation", "species_mix", "tall fan palms only"),
    ("wild and overgrown growth", "vegetation", "look", "wild and overgrown"),
    ("resort planting along the promenade", "vegetation", "look", "resort planting"),
    ("neat municipal beds", "vegetation", "look", "tidy municipal planting"),
    ("sun-bleached, parched planting", "vegetation", "look", "dry and sun-bleached"),
    ("giant plants towering over you", "vegetation", "size", "giant"),
]
STREET_VEG = [
    ("young leafy street trees", "vegetation", "size", "young"),
    ("big mature shade trees", "vegetation", "size", "mature"),
    ("unbroken clipped hedges along every fence", "vegetation", "hedges", "continuous hedges"),
    ("no hedges at all", "vegetation", "hedges", "no hedges"),
    ("wild, overgrown front gardens", "vegetation", "look", "wild and overgrown"),
    ("manicured verges", "vegetation", "look", "manicured"),
    ("dry, thirsty-looking planting", "vegetation", "look", "dry and sun-bleached"),
]
BEACH_PROPS = [
    ("towels thrown among the loungers", "props", "towels", "many towels among the loungers"),
    ("loungers and hardly a towel", "props", "towels", "mostly loungers"),
    ("buckets, coolers and bags left everywhere", "props", "clutter", "lots of clutter"),
    ("barely anything left lying about", "props", "clutter", "little clutter"),
    ("an umbrella over almost every lounger", "props", "umbrellas", "umbrellas on most loungers"),
    ("only a few umbrellas", "props", "umbrellas", "few umbrellas"),
    ("bright striped umbrellas over red and yellow fabric", "props", "palette", "white frames with red and yellow fabrics, striped umbrellas"),
    ("wooden frames with cream fabric and plain white umbrellas", "props", "palette", "natural wood frames with cream fabrics, plain white umbrellas"),
]
STREET_PROPS = [
    ("just lamps and bins", "props", "items", "lamps and bins only"),
    ("lamps, bins and hydrants", "props", "items", "lamps, bins and hydrants"),
    ("lamps, bins, hydrants, a bench and a mailbox", "props", "items", "lamps, bins, hydrants, a bench and a mailbox"),
    ("power poles with sagging wires and a stop sign", "props", "items", "lamps, power poles with wires, bins, hydrants, a stop sign"),
    ("a lamp every dozen metres", "props", "spacing", "lamps every 12 m"),
    ("lamps spaced well apart", "props", "spacing", "lamps every 24 m"),
    ("black lamps, blue bins, yellow hydrants", "props", "palette", "black lamps, blue bins, yellow hydrants"),
    ("weathered wooden poles and grey bins", "props", "palette", "weathered wooden poles, grey bins, red hydrants"),
]
DENSITY_WORDS = {"sparse": ["almost empty", "hardly anything about", "a quiet, bare feel"],
                 "normal": ["a normal amount of it", "the usual amount", "moderately busy"],
                 "dense": ["packed", "crowded with it", "densely filled"]}
MOODS = ["postcard", "cinematic", "documentary", "dreamy", "gritty", "serene", "stormy-light", "tropical"]

TEMPLATES = [
    "{time} on the {place}, {weather}: {a}, {b}, {c}",
    "a {mood} shot of the {place} {time}, {weather}, with {a} and {b}; {c}",
    "the {place} {time} under {weather} - {a}, {b}, {c}",
    "{place} scene {time}: {weather}, {a}, and {b}, {c}",
    "{time}, {weather} over the {place}. {a}. {b}. {c}",
    "a {mood} {place} {time}: {weather}, {a}, {b}, {c}",
]
PLACES = {"beach": ["beach", "shoreline", "resort beach"], "street": ["street", "suburban street", "road", "residential street"]}


def sample_scenes(n: int, seed: int):
    rng = random.Random(seed + 900)
    times, weathers = list(TIMES), list(WEATHER)
    out = []
    for i in range(n):
        world = WORLDS[i % 2]
        tod = times[(i // 2) % len(times)]
        wx = weathers[(i // (2 * len(times))) % len(weathers)] if i >= 2 * len(times) else rng.choice(weathers)
        density = rng.choice(list(DENSITY_WORDS))
        ground = rng.choice(BEACH_GROUND if world == "beach" else STREET_GROUND)
        veg = rng.choice(BEACH_VEG if world == "beach" else STREET_VEG)
        props = rng.choice(BEACH_PROPS if world == "beach" else STREET_PROPS)
        # the density word applies to whichever of vegetation / props the brief mentions last
        parts = [ground[0], veg[0], f"{props[0]}, {rng.choice(DENSITY_WORDS[density])}"]
        rng.shuffle(parts)
        mood = rng.choice(MOODS)
        text = rng.choice(TEMPLATES).format(time=rng.choice(TIMES[tod]), weather=rng.choice(WEATHER[wx]),
                                            place=rng.choice(PLACES[world]), mood=mood,
                                            a=parts[0], b=parts[1], c=parts[2])
        expect = [{"segment": s, "field": f, "value": v, "phrase": p} for p, s, f, v in (ground, veg, props)]
        expect.append({"segment": "props", "field": "density", "value": density, "phrase": "the density words"})
        out.append({"id": f"scene-{seed:02d}-{i:03d}", "text": text[0].upper() + text[1:],
                    "intent": {"world": world, "time_of_day": tod, "weather": wx, "mood": mood, "expect": expect}})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=60)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    rows = sample_scenes(a.n, a.seed)
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    write_jsonl(a.out, rows)
    print(f"wrote {len(rows)} scene briefs to {a.out}")
    for r in rows[:4]:
        print(" ", r["text"])


if __name__ == "__main__":
    main()
