---
name: subagent-review-loop
description: Run `/code-review` in a fresh-context subagent, triage and address findings, then re-review — looping until no significant findings remain. Use when the user says "subagent review loop", "review loop", "loop until clean", or asks to harden a branch/PR with iterative independent review. Argument is passed through to `/code-review` (default `high`).
argument-hint: "[code-review argument, default: high]"
---

# Subagent Review Loop

Iteratively review and harden the current branch/PR using **fresh-context subagents** to avoid same-session bias, then triage and address findings in the driver session, until a clean pass.

## Why a subagent

The driver session wrote (or just discussed) the code. Asking it to review itself produces confirmation bias. Spawning a subagent gives the review a clean context window — it sees only the diff, not the rationale that led to it.

## Argument

Pass-through to `/code-review`. Default to `high` if the user did not specify.

- User invocation: `/subagent-review-loop` → use `high`
- User invocation: `/subagent-review-loop ultra` → use `ultra`
- Any other token: pass it through verbatim

## Loop

Repeat until exit condition (below):

### 1. Spawn review subagent

Use the Agent tool with `subagent_type: "general-purpose"` (NOT `fork` — we want a fresh context). Prompt:

> Invoke the `/code-review` skill with argument `<arg>` on the current branch/PR. Return the full review output verbatim — findings, severities, file:line references. Do not summarize or filter. Do not attempt fixes.

### 2. Triage in the driver session

For each finding, classify:

- **Address directly (no ask):** bugfixes, correctness issues, performance improvements, dead code, missing error handling at boundaries, test gaps for existing behavior. Just fix it.
- **Surface to user first:** anything that changes user-facing behavior, public API shape, product semantics, or makes a non-obvious design tradeoff. Quote the finding and propose the change; wait for approval.
- **Dismiss:** false positives, nitpicks, suggestions that contradict established codebase patterns. Note why in the round summary.

When in doubt about whether something is user-facing → ask.

### 3. Implement

Apply the address-directly fixes. One commit per logical change is fine; batch the push to the end of the loop to avoid retriggering automated reviewers on every round.

### 4. Decide whether to loop again

**Exit when:** the most recent review round surfaced no significant findings (only nitpicks / already-addressed / dismissed-with-reason).

**Loop again when:** any Critical/Important finding was addressed this round, OR new findings appeared that weren't in the prior round.

**Hard cap:** stop after 5 rounds and report state to the user, even if findings remain. Diminishing returns past that point usually mean the remaining items need a human decision.

## Reporting

After exit, report:
- Rounds run
- Findings addressed (with commit refs)
- Findings surfaced to user / awaiting decision
- Findings dismissed (with one-line reason each)

## Guardrails

- **Never** let the subagent fix things — its job is review only. Fixes happen in the driver session so the user sees the diff.
- **Never** push between rounds if an automated reviewer (e.g. `claude[bot]`) runs on push — it will create a feedback loop of its own. Push once at the end.
- **Never** silently change product behavior to satisfy a review finding. Surface it.
