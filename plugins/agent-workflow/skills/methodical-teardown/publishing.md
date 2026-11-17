# Publishing for people and agents

## Publish v1 and keep it consistent

- **Timing.** Publish only after the end-to-end traces. If you must publish earlier, label the claims provisional.
- **Build the doc in two steps.**
  1. Create the skeleton: one tab or section per topic, each with a pending placeholder.
  2. Assign **one writer agent per tab, each working from one note**. The writer:
     - loads the doc tool's guides;
     - writes one section per edit;
     - uses tables over prose, sentences under 25 words, no emoji;
     - edits only its own tab;
     - reads diagrams, code spans and regexes back (or screenshots them) before reporting done.
- **Answer from the docs.** When the user asks "did we document this?", fold the answer into the note and the doc, not just the chat.

## Legibility rewrite (any human-facing tab that grew by accretion)

1. **Name the reader** and list the questions they arrive with, in order.
2. **Define two reading paths:** a two-minute skim and a twenty-minute study.
3. **Outline first**, in `research/NN-topic.outline.md`:
   - the section tree;
   - what stays in the body, answer first;
   - what goes to a self-contained appendix linked from the body: evidence, wire formats, test runs.
4. **Choose the altitude.**
   - Concept tabs stay at protocol level: who tells whom what, in what order, with what guarantee. No field names, endpoints or code.
   - Code-level detail goes in a separate "internals" appendix tab.
5. **Tame dense tables.**
   - Give each scenario a stable id (S1…Sn) and use it in the body, the headings and the evidence appendix.
   - Lead with a four-word verdict.
   - Put the evidence in appendix rows keyed by id.
6. **[opt] Outside review.** A reviewer persona, e.g. "a product engineer new to this platform", critiques the draft. Log each finding as change made or not taken.
7. **Draft**, then check against the old tab that every fact has a new home, and that none changed.
8. **Remove "earlier we thought…" narration.** It belongs in the corrections note.

## Agent entrypoint (`AGENT-ENTRYPOINT.md`)

One page. It covers:
- where each doc lives and how to read it;
- the notes index, with "later overrides earlier";
- the corrections to know first;
- how to run and check the prototype, and what was descoped;
- where the sources are, that they are untrusted, and their versions.

Keep it current as notes land. When sources move or vanish, tell readers to grep for the quoted symbol, not the file number.
