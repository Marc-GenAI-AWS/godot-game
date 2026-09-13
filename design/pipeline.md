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
  subgraph M4["M4 Agentic loop (built)"]
    L1[Director] --> L2[Specialists] --> L3[Verifier] --> L5[Publish]
    L3 -- evidence --> L4[Revise] --> L2
  end
  subgraph M5["M5 RL with verifiable rewards (later)"]
    R1[GRPO with the verifier as environment] --> R2[Anchor set + human review]
  end
  subgraph M6["M6 More segments (later)"]
    S1[ground/water, camera, fauna, props] --> S2[vegetation, architecture, crowd] --> S3[character body + motion]
  end
  M0 --> M1 --> M2 --> M3 --> M4
  M1 -. same verifier .-> M4
  M3 -. where SFT plateaus .-> M5
  M4 -. repeat per segment .-> M6
```

| Milestone | State | Exit criterion |
|---|---|---|
| M0 Gold scenes | done | two worlds under one contract, published |
| M1 Verifier | done for sky | gates veto, checks + judge agree with a human anchor set |
| M2 Data generation | running | ~100 verified sky examples across the brief space, held-out slice kept |
| M3 Fine-tune | next | a specialist whose held-out pass rate is within reach of the teacher's, registered |
| M4 Agentic loop | built, on the teacher | a new scene brief rendered and accepted with trained specialists, no hand edits |
| M5 RL | later | pass rate above SFT on the same held-out briefs, anchor agreement unchanged |
| M6 More segments | later | each segment through M1 to M4 |
