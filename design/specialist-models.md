# Specialised Models for Building Game Scenes

A design for training small, segment-specific models that build 3D game
scenes layer by layer, and for the agentic loop that lets them work together.
It is grounded in the Beach Walk scene in this repository, which was built by
hand in exactly the loop described here, with a large general model playing
every role.

Contents

1. Goal and shape of the system
2. The world contract
3. The specialists
4. The verifier
5. Generating the training data
6. Supervised fine-tuning
7. Reinforcement learning with verifiable rewards
8. The agentic loop
9. Building it on AWS with SageMaker AI
10. Roadmap, risks, and open questions

---

## 1. Goal and shape of the system

**Goal.** Given a brief, a paragraph of text or a reference clip, produce a
running game scene: terrain, water, sky, buildings, vegetation, props, crowd,
a hero character, fauna, camera. The output is source in an engine project
that exports to the web and runs at a fixed frame budget.

**Shape.** A scene is a stack of independent *layers*. Each layer is one source
file that builds itself from a shared *world context* and updates itself every
frame. Layers never call each other. This is already how `game/worlds/beach/` is built,
and it is the property that makes specialisation possible: a model that owns
one layer needs the contract, its brief, and its own file, and nothing else.

Three kinds of components:

| Component | What it is | How many |
|---|---|---|
| Specialists | Small models, one per segment, that write layer code | ~10 |
| Verifier | Deterministic checks plus one general vision judge | 1 pipeline |
| Director | A large general model that briefs, dispatches, and reviews | 1 |

Most of the system is plain code. The specialists are the only new models.

---

## 2. The world contract

The contract is everything a specialist is allowed to assume. It must be
frozen before any training data is collected, because every example encodes
it and a later change invalidates the dataset.

**Base class.** A layer subclasses `SceneLayer` and implements:

- `build()` – create nodes under itself, reading the context.
- `tick(delta)` – per-frame update.
- `on_world_wrapped(dz)` – shift any free-moving nodes when the world loops.

Repeating scenery subclasses `ChunkedLayer` and implements `build_chunk(chunk,
rng)` once; the base builds identical copies for seamless looping.

**World context.** A single object with the shared state:

- Constants: chunk period, axes (walk direction is -Z, sea is +X), slope.
- Live state: `time`, tide line, wind, `player`, `camera`, `player_phase`.
- Queries: `sand_height(x, z)`, `sea_level()`.
- Shared textures and a material cache.
- Signals: `player_step(pos, side, yaw)`, `world_wrapped(dz)`.
- A *palette* published by the sky layer at build time (new): sun direction,
  key/fill colours, fog colour, saturation. Other layers read it so the scene
  stays coherent.

**Conventions that must be written down**, because they caused every hard
failure in the hand-built version:

- Front faces are clockwise; terrain winding must be checked, not assumed.
- Models face -Z; imported glTF often faces +Z and needs a flip.
- The Compatibility renderer (web) has no built-in subsurface scattering, no
  SSR, and limited MultiMesh colour support; write shaders accordingly.
- Static geometry must be merged (`MeshBatch`); posed extras must be baked.
  Draw-call and triangle budgets are part of the contract.
- Import-time retargeting requires the *complete* option block in the
  `.import` file; partial blocks are silently discarded.

**Directory ownership (segment-first).** Each specialist owns one directory,
`game/segments/<segment>/`, holding the segment's shared generators and one
variant file per world (`variants/<world>.gd`). A world under `game/worlds/`
is only its assembly, its terrain context and its brief, which is what the
director owns. `game/core/` is the contract and nothing else.

**Capture recipes.** Each segment has a standard set of views the verifier
renders. They are part of the contract because a specialist's definition of
"done" is "passes its recipe".

---

## 3. The specialists

Each specialist owns one segment. The table gives its inputs, outputs, the
checks that define quality, and the difficulty of training it.

### 3.1 Ground and water

- **Owns:** heightfield mesh, sand and water shaders, tide line, shell scatter.
- **Brief inputs:** extents, shoreline position and shape, slope, wetness
  behaviour, wave scale, water palette.
- **Mechanical checks:** mesh winding outward; height query matches mesh
  within tolerance; water plane covers the view; triangle budget.
- **Judge rubric:** foam at the water's edge, depth gradient, wet-sand band,
  no visible tiling, matches reference palette.
- **Difficulty:** low. Dense rewards, no tools. First to train.

### 3.2 Sky, light, and grade

- **Owns:** environment, sun, fog, tonemapping, clouds; *publishes the palette*.
- **Brief inputs:** time of day, weather, mood words, reference frame.
- **Mechanical checks:** shadow direction matches stated sun angle; exposure
  in a sane range (mean luminance of a grey card); fog does not wash the
  foreground.
- **Judge rubric:** sky gradient and cloud character against reference,
  believable sun disc and haze, overall grade.
- **Difficulty:** low. Runs first in every scene because others read the palette.

### 3.3 Architecture

- **Owns:** buildings and hard landscape (boardwalks, walls, lamps, towers).
- **Brief inputs:** style (art deco, brutalist, medieval), density, height
  distribution, palette, setbacks from the path.
- **Mechanical checks:** no geometry in the walkable lane; all static geometry
  batched; draw-call budget; buildings sit on the ground.
- **Judge rubric:** facade variety, believable proportions, style match,
  silhouette against sky.
- **Difficulty:** medium. Large output space; benefits most from diverse briefs.

### 3.4 Vegetation

- **Owns:** species generators (palm, pine, hedge, grass) and placement rules.
- **Brief inputs:** biome, density bands, lane clearance, wind.
- **Mechanical checks:** placement respects clearance; alpha-cut foliage
  merged per plant; sway present when wind is non-zero.
- **Judge rubric:** species reads correctly, natural clustering, scale
  relative to people.
- **Difficulty:** medium.

### 3.5 Props and furniture

- **Owns:** small object generators and scatter; exposes *spots* people can use.
- **Brief inputs:** venue type (beach, market, campsite), density, clutter level.
- **Mechanical checks:** every object grounded; spots list non-empty and valid.
- **Judge rubric:** recognisable objects, sensible groupings, variety.
- **Difficulty:** low to medium. Good second target.

### 3.6 Character body

- **Owns:** turning a description into a rigged, textured body.
- **Brief inputs:** proportions, age, skin tone, garments, hair.
- **Tools:** Blender with MPFB2 (headless), the UV painting pipeline, the
  import retarget configuration.
- **Mechanical checks:** rig imports with humanoid bone names; height in
  range; facing direction; texture budget; garment masks cover the body
  regions they claim.
- **Judge rubric:** close-orbit views versus reference: proportions, hair,
  skin, clothing fidelity.
- **Difficulty:** high. Needs tool use inside the loop; slow episodes.

### 3.7 Character motion

- **Owns:** clip selection and retargeting, stride matching, footstep events,
  secondary motion (hair, cloth), camera-relative behaviours (head glance).
- **Brief inputs:** gait words (relaxed, brisk, limping), speed, surface.
- **Mechanical checks:** no foot sliding (foot velocity near zero at contact);
  stride length matches ground speed; loop seam continuity.
- **Judge rubric:** frame strips judged for naturalness and match to reference.
- **Difficulty:** high. Rewards need video-like input.

### 3.8 Crowd and behaviour

- **Owns:** who is where doing what; uses furniture spots; simple loops.
- **Brief inputs:** occupancy, activities, time of day.
- **Mechanical checks:** no overlaps; extras baked or budgeted; animated
  count under budget.
- **Judge rubric:** plausible scene life, variety of poses and clothing.
- **Difficulty:** medium.

### 3.9 Fauna and effects

- **Owns:** birds, footprints, dust, small ambient life.
- **Brief inputs:** species, count, behaviours (flock, flush, perch).
- **Mechanical checks:** heading matches velocity; effects fade and recycle.
- **Judge rubric:** isolated turntable of the creature plus in-scene behaviour.
- **Difficulty:** low. Self-contained; a good first target after ground/sky.

### 3.10 Camera

- **Owns:** framing, follow, stabilisation, inspect modes.
- **Brief inputs:** shot description, subject, feel (locked, handheld, drone).
- **Mechanical checks:** subject on screen and within a framing box; no
  clipping through ground; motion amplitude below a threshold when "stable".
- **Judge rubric:** composition versus reference frame.
- **Difficulty:** low. Tiny code, high impact, cheap to verify.

**Cross-cutting, not a specialist:** performance and conventions. Both live in
the contract and are enforced by the mechanical gates on every segment.

---

## 4. The verifier

One pipeline, mostly code, shared by data generation, evaluation, and RL.

```
brief + candidate layer
        │
        ▼
 1. Static gate      parses; subclasses the base; only allowed context access;
                     no forbidden APIs                          (code)
        │
        ▼
 2. Runtime gate     scene boots headless; no script errors;
                     frame time and draw calls under budget     (code)
        │
        ▼
 3. Geometry checks  segment-specific facts computed from the
                     scene or the render (winding, grounding,
                     shadow direction, framing box, stride)     (code)
        │
        ▼
 4. Capture          the segment's standard views                (code)
        │
        ▼
 5. Judge            one vision model call per view set with
                     rubric + reference crops → JSON scores
                     and one line of evidence per attribute     (model)
        │
        ▼
 6. Aggregate        gates veto; checks and judge blend into a
                     score; evidence becomes the revision brief (code)
```

Design rules:

- **Gates veto.** A judge score never excuses a failed gate.
- **Compare, don't rate**, wherever possible. Pairwise "which is closer to the
  reference" is more stable than absolute scores. Use absolute scores only
  for gating thresholds.
- **Judge at the right scale.** Characters and creatures are judged from a
  close orbit or an isolated turntable, never only from the wide shot.
- **Hold out references.** The judge compares against reference frames the
  policy never sees.
- **Human anchor set.** Keep 50 to 100 human-scored examples per segment.
  Re-run them whenever the judge prompt or model changes, and treat a drop
  in agreement as a broken verifier, not a worse policy.
- **The judge is a general model with a per-segment rubric.** Do not train
  it on outputs produced under its own scores. If it needs specialising, use
  human pairwise preferences collected from the loop.

**One verifier, three consumers.** The same pipeline serves data
generation (as a filter), training (as the reward), and the orchestrator (as
the acceptance test). It therefore returns both a continuous score, for
training, and a pass flag against per-segment thresholds, for acceptance,
along with the evidence strings that become revision briefs.

- The orchestrator never forms its own visual opinion of a sub-agent's
  output; it reads the verifier's verdict. Two judges that can disagree
  means sub-agents are trained by one and accepted by another.
- What the orchestrator adds is the *composite* check, the whole assembled
  scene, which runs through the same pipeline with a whole-scene rubric.
- The orchestrator may run the cheap stages alone (static and runtime gates)
  mid-loop to reject broken candidates in seconds before paying for capture
  and judging.

Cost: an episode on the current headless setup is about a minute, dominated
by the web export and browser boot. Native rendering on a GPU host brings it
to a few seconds; episodes are independent processes and parallelise freely.
A judge call on a 720p frame is roughly 1,500 input tokens.

---

## 5. Generating the training data

Examples are not written by hand. They are sampled from a strong model and
filtered by the verifier. The verifier must exist before data generation.

**Per segment:**

1. **Brief sampler.** A structured generator over the segment's brief
   space: biome, time of day, weather, style, density, budget, palette.
   Diversity here is the single biggest lever. A sky specialist trained only
   on tropical noon will not do overcast dusk.
2. **Teacher generation.** A large model writes the layer from
   contract + brief. Sample several candidates per brief at moderate
   temperature.
3. **Filter.** Run the verifier. Keep passes as SFT examples. Keep fails,
   with their evidence, for preference data later.
4. **Iterate a fraction.** For some briefs, feed the evidence back and let
   the teacher revise. The (brief, evidence, revised layer) triples train the
   revision behaviour the agentic loop will rely on.
5. **Second world.** Before scaling, build at least one scene in a different
   biome under the same contract (a forest trail, a night street). It proves
   the contract generalises and gives the samplers a second anchor.

**Scale.** Hundreds of verified examples per segment across genuinely
different briefs are worth more than thousands of near-duplicates. Segment
difficulty sets the count: sky and camera saturate early; architecture and
characters need the most.

**Bookkeeping.** Every example stores brief, contract version, layer source,
verifier scores, evidence, capture images, and teacher model id. Git history
of this repository is a small seed set of the same shape.

---

## 6. Supervised fine-tuning

One small model per segment, or one model with a segment token if the
segments are close in style. Start with one per segment; merge later if
evaluation shows no loss.

- **Input:** contract excerpt (base class API, context fields, conventions,
  capture recipe) + brief.
- **Output:** the complete layer file.
- **Also train:** the revision format, (brief, previous layer, evidence) →
  revised layer, from the iterated fraction of the data.
- **Evaluate:** held-out briefs through the verifier; pass rate, mean judge
  score, and agreement with the human anchor set. Also a tiny *composition*
  eval: assemble a full scene from all specialists' outputs and verify it as
  a whole, to catch layers that pass alone and clash together.

Expect SFT to capture most of the value: conventions, batching idioms,
shader patterns. Where the pass rate plateaus below target, move to RL.

---

## 7. Reinforcement learning with verifiable rewards

Use RL where SFT plateaus, and only on segments with dense, honest rewards.

**Episode.** Prompt = contract + brief. Action = layer file (or a revision
given evidence). Environment = verifier. Reward:

```
reward = 0                                  if any gate fails
       = w_c · checks + w_j · judge_bonus   otherwise
```

- `checks` are the numeric geometry/budget measures, normalised.
- `judge_bonus` is a pairwise win rate against held-out references or the
  SFT policy's own output, not an absolute score.

**Order of segments:** sky → ground/water → camera → fauna → props →
vegetation → architecture → crowd → motion → body. The first four have cheap
episodes and rewards that are hard to game. Body and motion require tool use
inside the episode and video-like judging; do them last or leave them at SFT.

**Guarding the reward.**

- Freeze everything outside the layer under training, with fixed seeds, so
  reward variance comes from the policy.
- Randomise the capture slightly (camera jitter, time of day within the
  brief) so the policy cannot overfit a single pixel layout.
- Re-run the human anchor set each training run; stop if agreement drops.
- Log the top-scoring outputs for human review every N steps. Reward hacking
  shows up here first.

---

## 8. The agentic loop

The loop turns a scene brief into a running scene. It is the process that
built the beach by hand, made explicit.

```
                 ┌──────────────────────────────┐
  scene brief ──▶│ Director (large general model)│
  or reference   │  - decompose into segment    │
                 │    briefs + palette + budgets │
                 └──────────────┬───────────────┘
                                │ briefs (parallel, except ordering below)
        ┌───────────┬───────────┼───────────┬───────────┐
        ▼           ▼           ▼           ▼           ▼
     sky spec   ground spec  arch spec  ...        camera spec
        │           │           │           │           │
        └───────────┴───────────┼───────────┴───────────┘
                                ▼
                     assemble scene from layers
                                │
                                ▼
                            Verifier
                     per-layer + composite views
                                │
                 ┌──────────────┴───────────────┐
                 │ pass                          │ fail / low score
                 ▼                               ▼
              publish                  evidence → Director → revision
                                       briefs → specialists (revise mode)
```

**Ordering.** Sky runs first and publishes the palette. Furniture runs before
crowd because crowd consumes spots. The player runs before camera. Everything
else is parallel.

**Director responsibilities.**

- Turn a reference into per-segment briefs. For a clip: extract frames, crop
  regions, describe each segment in the brief schema, pick budgets.
- Enforce global coherence: palette, scale, style words shared across briefs.
- Route verifier evidence back as revision briefs; decide when to stop.
- Own the composite review: judge the assembled scene as a whole and
  attribute problems to segments.

**Specialist responsibilities.** Write or revise one layer from a brief.
Never touch another layer. Never change the contract.

**Verifier responsibilities.** Score per layer and per composite; produce
evidence and a pass flag; never be edited by the loop. It is the same
verifier used to filter training data and to compute rewards, so acceptance
in the loop and quality in training are one definition.

**Budget and stopping.** Each segment gets a revision budget (three rounds is
plenty in practice). The director stops when the composite passes or the
budget is exhausted, and reports what remains unresolved rather than
looping.

**Human in the loop.** Two touchpoints: approve the director's briefs before
generation (cheap, catches misread references), and review the composite at
the end. Everything between is automatic.

**Operational notes from the hand-built loop:**

- Publish only after the composite passes. A broken layer once went live
  for two minutes because export happened before the parse check.
- Keep the capture harness deterministic: fixed seeds, cache disabled,
  timestamps as parameters.
- Keep tool-heavy segments (character body) off the critical path; run them
  ahead of time and cache the assets.

---

## 9. Building it on AWS with SageMaker AI

The pipeline maps onto SageMaker AI and Bedrock without bending it. Training,
data, labelling, registry and serving are covered by managed services; the one
piece with no turnkey answer is the RL environment, because episodes render a
game scene, and that is a custom container on any cloud.

| Pipeline stage | AWS piece |
|---|---|
| Brief sampling and teacher generation | SageMaker Processing jobs; Claude on Bedrock as the teacher |
| Verifier, mechanical stages | Processing jobs on a custom GPU container (Godot headless + Chromium/EGL, same recipe as `shots/`) |
| Verifier, judge stage | Claude on Bedrock with image input, called from the same job |
| Human anchor set, pairwise preferences | Ground Truth labelling jobs with a custom image-comparison task |
| Dataset versioning | S3 with versioned prefixes keyed by contract version (Feature Store optional) |
| SFT of specialists | Training jobs on the Hugging Face / PyTorch containers, or JumpStart fine-tuning of open models (7B–14B code models); HyperPod to train many segments at once |
| RL with verifiable rewards | Training jobs or HyperPod running TRL / veRL, with the verifier container as the environment |
| Evaluation and registry | Model Registry; the verifier's held-out eval is the approval gate |
| Serving specialists | Real-time or async endpoints, one per segment or a multi-model endpoint |
| Director and orchestration | Bedrock Agents, or Step Functions driving Bedrock calls and the specialist endpoints |
| Pipeline glue | SageMaker Pipelines: generate → filter → train → eval → register |

**Design choices to make early**

- *Where the render environment lives.* For data generation and evaluation,
  Processing jobs are enough: batch a few hundred briefs per job, render,
  score, write to S3. For RL the environment must answer the trainer
  quickly, so it runs inside the same HyperPod cluster, or on a fleet of GPU
  workers the trainer calls over the network. Build the verifier as one
  container image from the start and use it in both modes. On x86 with an
  NVIDIA GPU it renders natively and an episode is seconds, not the minute
  it takes on the arm64 development box.
- *Base model for the specialists.* Fine-tuning open weights on SageMaker
  gives full control and cheap inference for the many-call specialist role,
  and leaves RL open. Bedrock custom-model fine-tuning is operationally
  simpler but constrains RL. Recommended: open weights on SageMaker for
  specialists; Bedrock for the judge and director, where the strongest
  model matters and calls are few.

**What AWS does not provide**

- A managed RLVR loop. You bring the RL library and the environment. This
  is true of every cloud today.
- Anything about scene quality. The contract, capture recipes, rubrics and
  anchor sets are yours to write regardless of platform, and are most of
  the intellectual work in this document.

**First milestone.** One SageMaker Pipeline that takes a batch of sky briefs,
generates layers with Claude on Bedrock, runs the verifier container, writes
verified examples to S3, and fine-tunes one specialist. That exercises every
service in the table except RL, and shows within days whether the loop yields
training data at the needed rate. Develop the verifier container on an x86
GPU machine; the arm64 box used for the prototype is the wrong architecture
for a SageMaker image.

---

## 10. Roadmap, risks, and open questions

**Roadmap**

1. Freeze the contract: rename the base to `SceneLayer`, add the palette
   publication, write the conventions and capture recipes into a spec file.
2. Build the verifier: gates, geometry checks, capture, judge, aggregate.
   Wire it to the existing `shots/` harness.
3. Build a second scene under the contract (different biome) and refine the
   contract until both scenes pass unchanged.
4. Brief samplers and teacher generation for sky, ground/water, camera,
   fauna, props. Collect a human anchor set.
5. SFT those five. Evaluate individually and in composition.
6. RL on sky and ground/water; extend if it earns its cost.
7. Architecture, vegetation, crowd through the same path.
8. Character body and motion at SFT with cached assets; RL later if ever.
9. Director prompt and the loop; run end to end on a new brief.

**Risks**

- *Contract drift.* The most likely way to waste the dataset. Version it and
  refuse examples from old versions.
- *Judge drift and reward hacking.* Covered by anchor sets, pairwise scoring,
  held-out references, and periodic human review of top outputs.
- *Over-fitting one world.* The second-scene step exists for this.
- *Engine coupling.* The specialists learn one engine's idioms. Keep the
  contract engine-agnostic in wording so a port is a data-generation run,
  not a redesign.

**Open questions**

- Whether one small model with segment tokens matches ten separate ones.
- How much of the character pipeline should be model versus fixed tooling;
  the generation step may stay a script with the model choosing parameters.
- Whether the judge needs video input for motion, or frame strips suffice.
- The right frame budget and capture resolution for training-time verification
  versus final quality.
