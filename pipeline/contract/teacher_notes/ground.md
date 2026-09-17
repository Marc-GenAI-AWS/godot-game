# Notes for a local teacher writing ground layers

Appended to the contract when generating with `--notes`. Written from what a local
Qwen3-Coder-Next run actually got wrong across 144 candidates on 72 street briefs
(21 gate failures, mean "features" score 3.88 against Claude's 5.41). It is not style
advice: every point below is a mistake that cost real candidates.

## Scoping — the single biggest cause of rejected layers

Two thirds of the failures were one error: **"There is already a variable named X
declared in this scope."**

GDScript does not give `for` and `if` blocks their own scope the way C or Rust do. A
variable declared inside a loop belongs to the whole function, so declaring the same name
in a second loop — or in a nested loop — is a hard parse error, and nothing in the file
loads.

```gdscript
for z in range(0, 40, 4):
    var seg := make_slab(z)        # 'seg' now belongs to the function
for z2 in range(0, 40, 6):
    var seg := make_joint(z2)      # ERROR: already declared
```

Give every loop and every block its own names — `slab_seg`, `joint_seg`, `row_z`,
`ring_z` — or declare the variable once before the loops and assign inside them. Prefer
descriptive prefixes over numbered suffixes: it is easier to keep straight in a 150-line
file, which is the length these layers run to.

Check the same way for the loop variable itself: `for z in ...` twice in one function is
fine, but `var z := ...` after a `for z in ...` is not.

## Brackets

Three failures were a stray closing brace or parenthesis, usually at the end of a long
array of coordinates. When a literal runs over several lines, count the closers before
moving on; a single extra one discards the whole file.

## Types where the inference cannot see through a call

```gdscript
var t := lerp(a, b, 0.5)           # fails: "has no known type"
var t: float = lerp(a, b, 0.5)     # fine
```

Anything whose right-hand side is a call the parser cannot resolve — `lerp`, `clamp`,
`Callable.call`, a helper of your own — needs an explicit type. When in doubt, write the
type.

## Implement every field of the brief, visibly

The judge scores each field of the brief separately, and "features" is where these layers
lose most: the brief names markings, kerbs, sidewalk joints, lawns and a surface tone, and
a layer that renders good asphalt but forgets the dashed centre line scores as a failure
even though it looks fine.

Before finishing, walk the brief field by field and name where each one is realised in the
code. A field that is hard to see from the camera path is worth exaggerating slightly —
the judge only sees three fixed views, and something subtle enough to miss scores as absent.

## Surface

Flat albedo reads as plastic and scores badly. Vary the material the way the shipped
layers do: small per-instance albedo jitter, roughness that differs between the road, the
kerb and the slabs, and joints or wear that break up a large flat area. Two materials that
differ only in colour will be marked down; the brief's tone should change how the surface
*reads*, not just its RGB value.
