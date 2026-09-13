# Pipeline stages and milestones

![pipeline](pipeline.png)

Source: `design/pipeline.dot` (`dot -Tpng design/pipeline.dot -o design/pipeline.png`).
The same flow in Mermaid, for places that render it:

```mermaid
flowchart TB
  subgraph M0["M0 Gold scenes (done)"]
    A1[Beach Walk + Street Drive] --> A2[World contract: SceneLayer, WorldContext, swap hook]
  end
  subgraph M1["M1 Verifier (done for sky)"]
    V1[Static gate] --> V2[Runtime gate] --> V3[Native capture] --> V4[Checks] --> V5[Judge: Claude + rubric] --> V6[Aggregate: score, pass, evidence]
  end
  subgraph M2["M2 Data generation (running)"]
    D1[Brief sampler] --> D2[Teacher: Claude Sonnet 5] --> D3[Verify] --> D5[SFT dataset]
    D3 -- fails + evidence --> D4[Revise] --> D3
  end
  subgraph M3["M3 Fine-tune specialists (next, SageMaker)"]
    T1[SFT job: Qwen2.5-Coder-7B + LoRA] --> T2[Bake-off 1.5B / 3B / 7B] --> T3[Evaluate on held-out briefs] --> T4[Model Registry]
  end
  subgraph M4["M4 Agentic loop (built for one segment; composite verifier next)"]
    L1[Director] --> L2[Specialists, dependency order] --> L3[Per-layer verifier] --> L3b[Composite verifier: whole scene] --> L5[Publish]
    L3b -- evidence --> L4[Revise] --> L2
  end
  subgraph M5["M5 Segments through M1-M4 (contract, rubric, sampler, checks, recipe each)"]
    G0[sky: done] --> G1[ground / water] --> G2[camera] --> G3[fauna] --> G4[props] --> G5[vegetation] --> G6[architecture] --> G7[crowd] --> G8[characters] --> G9[vehicles + player modes]
  end
  subgraph M6["M6 RL with verifiable rewards (where SFT plateaus)"]
    R1[GRPO with the verifier as environment] --> R2[Anchor set + human review]
  end
  subgraph M7["M7 Holistic scene generation"]
    H1[Second world under the contract] --> H2[Director writes the world assembly] --> H3[All specialists + composite verifier]
  end
  M0 --> M1 --> M2 --> M3 --> M4 --> M5
  M1 -. same verifier .-> M4
  M5 -. cheap rewards first .-> M6
  M5 --> M7
  L3b -. makes M7 possible .-> M7
```

| Milestone | State | Exit criterion |
|---|---|---|
| M0 Gold scenes | done | two worlds under one contract, published |
| M1 Verifier | done for sky | gates veto, checks + judge agree with a human anchor set |
| M2 Data generation | running | ~100 verified sky examples across the brief space, held-out slice kept |
| M3 Fine-tune | next | a specialist whose held-out pass rate is within reach of the teacher's, registered |
| M4 Agentic loop | built for one segment | composite verifier added; a new scene brief rendered and accepted with trained specialists, no hand edits |
| M5 Segments | sky only | each segment has a contract, rubric, sampler, checks and capture recipe, and a specialist through M1 to M4, in the order shown |
| M6 RL | later | pass rate above SFT on the same held-out briefs, anchor agreement unchanged |
| M7 Holistic generation | later | one brief in, a playable scene out: the director writes the world assembly, every layer comes from a specialist, the composite verifier accepts |

**Composite verifier.** The per-layer verifier renders one candidate inside
the shipped scene and scores it against its segment brief. The composite
verifier renders the whole assembled scene, scores it with a whole-scene
rubric (coherence of palette, scale and style; nothing intersecting; budget
as a whole), and attributes each problem to a segment so the director can
route revision briefs. It is what catches layers that pass alone and clash
together, and it is the acceptance test for M7.
