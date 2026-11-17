# Gap analysis and jobs-to-be-done

## Gap analysis (builder's view)

1. **Taxonomy.** List every question a senior engineer building something similar would ask, grouped into about 20 areas: data model, persistence, concurrency, editor, rendering, agent path, export, permissions, failure modes, ops, and so on.
2. **Coverage matrix.** For each question: answered, partial or not, with the note § that answers it.
3. **Investigate the top 10–15 unanswered questions** from the sources, using helpers with precise questions and file pointers.
4. **Boundary.** State what these sources can't answer (server internals, host shell, another client), each with a concrete way to get it and its expected yield.
5. **Rank next steps by value to the builder.** Run the top one right away; it often sends you back to acquisition.

Done when every question has a coverage mark and every boundary item has an acquisition plan.

## Jobs, stories and acceptance criteria

The output is a requirements view that can be traced to evidence. Its parts:

- **Actors.** Humans by role, **AI agents as first-class actors** (they author and edit too), and the platform where relevant.
- **Jobs (10–20).**
  - Each is written "When …, I want to …, so I can …" and tagged `[I]`, with the observed behaviour that implies it cited.
  - Split them into shared jobs and product-specific jobs.
  - Give them stable ids (`J-C1`, `J-S3`, …).
- **Story-map backbone.** The user's journey, e.g. create → first draft → edit → review → co-edit → present/read → export/share → recover.
- **Stories** (job stories for humans, agent stories for AI actors). Each has:
  - Given/When/Then AC taken **only from observed behaviour, with a citation**;
  - the design decision that serves the story;
  - **the builder's decision point**: the alternatives not taken, and their cost;
  - a confidence.
- **Diagnosis.**
  - Jobs that are poorly served.
  - Behaviour that serves no clear job.
  - Dormant or flagged features, which hint at where the product is heading.
- **Traceability table:** story · job · evidence · confidence.
- **Contradictions found in code.** This list feeds a corrections pass: verify each item in code, fix every note and tab, and log it in the corrections note.

**Evidence of intent beyond docs:**
- UI copy, empty states and error strings;
- telemetry event names;
- instructions given to AI agents;
- feature flags.

Use the strongest model as lead, with parallel bounded miners: one per evidence type.
