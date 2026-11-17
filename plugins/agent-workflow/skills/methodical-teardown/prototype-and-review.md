# Implementation spec, isolated prototype, review loop

## Spec (when rebuilding, not just understanding)

1. **Audit each job and subsystem as re-implementation grade:** yes, partial or no.
2. **Fill the gaps from the sources:** data shapes, algorithms, exact constants, state machines (as code blocks), invariants and edge cases.
   - Start with the hand-built parts. Library-backed parts need less.
   - **The input contract comes first:** the format agents and users write, and its grammar. Without it, a prototype built alongside the spec will get the format wrong.
3. **The spec is for agents.** Human readers get concept-level tabs (see publishing.md).

## Isolated prototype

**Purpose.** Learn which gaps matter, and test design alternatives. It is not a product.

**Why isolated.** A fresh repo means the prototype tests the design itself. It isn't bogged down by a host repo's existing cruft, conventions, dependencies or constraints. Port the learnings into the real codebase later, through the hand-off briefs.

**Before launch:**
- **Decide scope cuts with the user:**
  - keep the uncertain, architecture-shaping parts (concurrency, undo, recovery, the agent write path);
  - simplify or drop fidelity work (export formats, polish, mobile, accessibility, extra media).
  - Record the cuts as an ADR.
- **Give the full source inventory** in the first prompt: notes, jobs, spec, and every extracted source path. The agent entrypoint makes this cheap.

**Brief requirements:**
- A new repo or folder, separate from the host codebase, with no production credentials. Commits stay local and are never pushed.
- `docs/data-model.md` written **before** code. One ADR per judgement call.
- A concurrency or consistency choice argued against the main collaboration job, avoiding the failure modes found in the reference.
- `docs/jtbd-coverage.md`: one row per job (implemented, partial, or excluded with a reason).
- An AI-agent write path that works without an API key (MCP server plus a scripted demo agent).
- Unit tests plus at least one multi-client end-to-end test. **Actually run it**; start a dev server on non-default ports, never the user's.
- A running `docs/learnings.md`.

## Review loop (required if the prototype ran)

1. **Adversarial adherence review.** The strongest model leads, with 2–3 helpers, read-only. For each subsystem, choose one verdict:
   - ADHERES;
   - DEPARTS-JUSTIFIED;
   - DEPARTS-UNJUSTIFIED;
   - MISSING;
   - REGRESSION.

   Cite both sides. **Check the prototype's claims about itself by running it.** Check it against the reference's known failure modes (lost updates, stale writes, races) and **security** (stored XSS, injection). For each bug, give a reproduction and a recommendation: adopt-reference, keep-departure or fix-bug.
2. **Propagation audit, in parallel.** A matrix of learning × where it should live (notes, jobs, spec, docs), with the suggested wording.
3. **Fixes.** Test-first, one commit per fix, security first, then concurrency.
4. **Propagation.** Update the markdown notes first, then the docs. Mark bug statuses from the git log.

**Done when:**
- typecheck and tests are green;
- every bug is fixed with a commit or deferred with a reason;
- every learning is in its home.

**Hand-off to a real build:**
- A divergence audit that lists deliberate divergences, scope cuts, and "reference flaws we must not copy", each with the smallest safe alternative.
- A standing build brief plus one brief per task. Each new session starts with "Read plans/X-BRIEF.md and follow it".
