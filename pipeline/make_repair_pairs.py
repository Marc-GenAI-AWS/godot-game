"""Synthetic repair examples: a passing layer with one realistic error injected, the
verifier's real rejection message, and the original layer as the fix. They teach a
specialist to repair code from gate evidence, which the teacher's own revisions rarely
show (on Sep 14, 25 of 222 passing revisions fixed a gate failure; the rest fixed judge
complaints), and the small models repeated the same parse error across every round.

    pipeline/.venv/bin/python pipeline/make_repair_pairs.py --runs veg1 props1 --workers 3

The error kinds are the ones the verifier sees most from the models: a missing closing
parenthesis, a duplicated variable, an unterminated string, Vector3 with two arguments,
an invented engine constant, a misspelt variable, an untyped read from a dictionary.
An injected error is kept only if the real static or runtime gate rejects it; the
evidence is exactly what the verifier would say. Output: runs/<run>/repairs.jsonl
(rows build_sft.py reads as mode "repair") and the broken files in runs/<run>/repairs/.
Needs no Bedrock; the runtime gate is a headless Godot boot per example.
"""
import argparse
import random
import re
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from common import RUNS, SEGMENTS, read, read_jsonl, write_jsonl
from teacher import revise_prompt
from verify import install_candidate, runtime_gate, static_gate


def drop_paren(code, rng):
    ls = code.split("\n")
    idx = [i for i, l in enumerate(ls) if l.rstrip().endswith(")") and "(" in l and not l.strip().startswith("#")]
    if not idx:
        return None
    i = rng.choice(idx)
    ls[i] = ls[i].rstrip()[:-1]
    return "\n".join(ls)


def duplicate_var(code, rng):
    ls = code.split("\n")
    idx = [i for i, l in enumerate(ls) if re.match(r"^\t+var \w+.*[^,(\[{\\]\s*$", l)]
    if not idx:
        return None
    i = rng.choice(idx)
    ls.insert(i + 1, ls[i])
    return "\n".join(ls)


def unterminated_string(code, rng):
    ls = code.split("\n")
    idx = [i for i, l in enumerate(ls) if re.search(r'"[^"\n]+"', l) and not l.strip().startswith("#")]
    if not idx:
        return None
    i = rng.choice(idx)
    m = list(re.finditer(r'"[^"\n]+"', ls[i]))[-1]
    ls[i] = ls[i][:m.end() - 1] + ls[i][m.end():]
    return "\n".join(ls)


def wrong_arity(code, rng):
    ms = [m for m in re.finditer(r"Vector3\(([^()\n]+),([^(),\n]+)\)", code) if m.group(1).count(",") == 1]
    if not ms:
        return None
    m = rng.choice(ms)
    return code[:m.start()] + f"Vector3({m.group(1)})" + code[m.end():]


def invented_constant(code, rng):
    ms = list(re.finditer(r"\b(Environment|BaseMaterial3D|StandardMaterial3D|Mesh|GeometryInstance3D|ProceduralSkyMaterial|"
                          r"Light3D|DirectionalLight3D|Label3D|Sprite3D|SpriteBase3D)\.([A-Z][A-Z0-9_]+)\b", code))
    if not ms:
        return None
    m = rng.choice(ms)
    parts = m.group(2).split("_")
    fake = "_".join(parts[:-1] + ["NONE"]) if len(parts) > 1 else m.group(2) + "_NONE"
    if fake == m.group(2):
        fake = "_".join(parts[:-1] + ["DEFAULT"])
    return code[:m.start(2)] + fake + code[m.end(2):]


def undeclared_identifier(code, rng):
    names = re.findall(r"^\t+var (\w{4,})\b", code, re.M)
    rng.shuffle(names)
    for name in names:
        uses = list(re.finditer(rf"(?<![\w.]){name}\b", code))
        if len(uses) >= 2:
            m = uses[-1]   # a later use, not the declaration
            return code[:m.start()] + name[:-1] + code[m.end():]
    return None


def untyped_variant(code, rng):
    ms = list(re.finditer(r"^(\t+)var (\w+): [\w\[\]]+ = (\w+\[[^\]\n]+\])\s*$", code, re.M))
    if not ms:
        return None
    m = rng.choice(ms)
    return code[:m.start()] + f"{m.group(1)}var {m.group(2)} := {m.group(3)}" + code[m.end():]


CORRUPTIONS = {"drop_paren": drop_paren, "duplicate_var": duplicate_var, "unterminated_string": unterminated_string,
               "wrong_arity": wrong_arity, "invented_constant": invented_constant,
               "undeclared_identifier": undeclared_identifier, "untyped_variant": untyped_variant}


def make_one(row: dict, kind: str, seed: int, out_dir: Path):
    code = read(row["path"])
    broken = CORRUPTIONS[kind](code, random.Random(seed))
    if not broken or broken == code:
        return None
    seg, brief = row["segment"], row["brief"]
    world = brief.get("world", SEGMENTS[seg]["world"])
    cid = f"{row['candidate']}_fix"
    problems = static_gate(broken, seg)
    if problems:
        evidence = "static gate: " + "; ".join(problems)
    else:
        ok, errors = runtime_gate(world, f"{seg}:{install_candidate(seg, cid, broken)}")
        if ok:
            return None
        evidence = "runtime gate: " + " | ".join(errors)
    bp = out_dir / "repairs" / f"{cid}.gd"
    bp.write_text(broken)
    return {"candidate": cid, "brief_id": row["brief_id"], "segment": seg, "brief": brief, "mode": "repair",
            "repair_kind": kind, "prompt": revise_prompt(brief, broken, evidence), "path": row["path"],
            "broken_path": str(bp), "pass": True, "score": row.get("score", 0.0), "evidence": evidence,
            "source_candidate": row["candidate"]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", nargs="+", required=True, help="run directories under pipeline/runs")
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--seed", type=int, default=0)
    a = ap.parse_args()
    for run in a.runs:
        out_dir = RUNS / run
        rows = []
        for name in ("verified.jsonl", "verified_rev.jsonl"):
            p = out_dir / name
            if p.exists():
                rows += [r for r in read_jsonl(p) if r.get("pass") and Path(r["path"]).exists()]
        (out_dir / "repairs").mkdir(parents=True, exist_ok=True)
        rng = random.Random(f"{a.seed}-{run}")
        jobs = []
        for r in rows:
            order = list(CORRUPTIONS)
            rng.shuffle(order)
            jobs.append((r, order, rng.randrange(1 << 30)))

        def work(job):
            r, order, seed = job
            for kind in order:   # the first error kind that applies to this layer and that a gate rejects
                try:
                    res = make_one(r, kind, seed, out_dir)
                except Exception as e:
                    print(f"  {r['candidate']} {kind}: {str(e)[:120]}", flush=True)
                    res = None
                if res:
                    return res
            return None

        with ThreadPoolExecutor(max(1, a.workers)) as ex:
            out = [x for x in ex.map(work, jobs) if x]
        write_jsonl(out_dir / "repairs.jsonl", out)
        print(f"{run}: {len(out)} repair examples from {len(rows)} passing layers "
              f"{dict(Counter(x['repair_kind'] for x in out))}", flush=True)


if __name__ == "__main__":
    main()
