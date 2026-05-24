---
name: adversarial-review
description: Stress-test any artifact by spawning an Adversary agent (finds problems) then a Counterweight agent (calibrates findings). Use when the user says "adversarial review", "challenge this", "stress test this", "red team this", or wants a second opinion on a design or implementation.
argument-hint: "[path/to/artifact or PR number] — optional, inferred from context if omitted"
---

# Adversarial Review

Stress-test any artifact by spawning an **Adversary** (finds problems) then a **Counterweight** (calibrates findings). The user receives a structured, evidence-checked report and decides what to act on.

## $ARGUMENTS

Optional path to artifact, PR number, or branch name. If omitted, infer from context.

## Step 1: Identify the Artifact

**If an argument was provided:**
- File path → read the file
- PR number → fetch the PR with `gh pr view <number> --json title,body,files` and the diff with `gh pr diff <number>`
- Branch name → diff against the base with `git diff main...<branch>`

**If no argument was provided:**
- Infer from context: current branch diff (`git diff main...HEAD`), a recently written spec file, or an open PR on the current branch (`gh pr view`)
- If multiple candidates are plausible, ask the user which one to review

**Hard constraints:**
- The artifact must be concrete: a file, a diff, or a PR. Do not review conversation context alone.
- If the user is mid-brainstorm with nothing written down, tell them: "Write the idea to a file first, then invoke adversarial-review on that file."
- If it is still ambiguous after checking context, ask the user before proceeding.

## Step 2: Classify the Artifact

Read the artifact and determine:

- **Type:** spec, code diff, PR, config, architecture doc, API change, infra change
- **Scope:** single file, single module, multi-module, cross-system
- **Domain:** auth, data model, API, UI, infra, other
- **Altitude:** `design` (specs, design docs, architecture) | `implementation` (code diffs, configs, PRs) | `mixed` (a spec with embedded code samples, or a PR that introduces a new design)

Type drives persona selection (Step 3). Altitude scopes the Adversary's focus (Step 3) and the report layout (Step 5).

Announce to the user:

> Reviewing **{artifact name}** ({type}, {scope}, {altitude} altitude). Spawning **{persona}** adversary...

## Step 3: Spawn the Adversary

### Persona Selection

| Artifact type | Persona | Focus |
|---|---|---|
| Spec / design doc | Feasibility skeptic | Claims vs codebase reality, scope gaps, missing considerations |
| Code diff / PR | Integration adversary | Callers, cross-module boundaries, edge cases, test coverage |
| Config / infra | Blast radius analyst | What breaks if wrong, deploy ordering, rollback safety |
| API change | Consumer advocate | All consumers accounted for, backwards compat, migration path |
| Architecture doc | Scalability skeptic | Bottlenecks, failure cascades, operational blind spots |

Select the persona whose artifact type best matches the classification from Step 2. If the artifact spans multiple types, pick the dominant concern. For subsequent rounds, pick the next most relevant unused persona.

### Dispatch

Spawn a background subagent using the Agent tool with the following prompt:

---

You are an adversarial reviewer — a **{persona}**. Your focus: {focus}.

**Mandate:** Find blind spots, flawed assumptions, and failure modes in the artifact under review. Do NOT propose fixes, rewrites, or alternatives. Only identify problems.

**Altitude focus:** This artifact is at the **{altitude}** level. Your main focus must match.

- **Design altitude:** challenge framing, assumptions, scope, claims-vs-reality, missing considerations, whether the approach is sound. Do NOT lead with implementation specifics (FD lifecycle, byte counts, exact line numbers, function signatures) unless they invalidate a design assumption.
- **Implementation altitude:** challenge correctness, edge cases, callers, concurrency, test coverage, integration boundaries.
- **Mixed:** apply both, but tag each finding with which altitude it addresses.

If during investigation you surface findings at a *different* altitude than the artifact, mark them with `altitude: off` in the output (see Output Format). Do not suppress them — they're useful as appendix material — but they must not crowd out the main-altitude findings.

**Artifact under review:**

{artifact_content}

<!-- Round 2+ only — include the following two sections if this is a subsequent round -->
**Previously confirmed challenges (do not re-raise these):**

{confirmed_challenges_summary}

**Explorer context (prior investigation findings):**

{explorer_output}
<!-- End round 2+ sections -->

**Evidence-Gating Rule:** Every challenge MUST cite specific evidence: a file path, line range, grep result, or concrete scenario. If you cannot point to where the problem manifests, do not raise it.

Bad example: "Consider error handling."

Good example: "The function `processOrder()` at `src/orders/process.py:45` does not handle the case where `order.items` is empty, which will raise an IndexError on line 52."

**Precision Bias:** Lean toward false negatives over false positives. Only flag findings you'd bet >70% on — better to miss a marginal issue than bury real ones in noise. A short, sharp list of high-confidence challenges is more useful than an exhaustive list with mixed confidence.

**Investigation Strategy:**

- Grep for callers of any function or interface the artifact modifies
- Check imports of any module the artifact touches
- Read adjacent files that might be affected
- Look for test files that cover the modified code
- Trace cross-module boundaries
- Web search for relevant documentation, known issues, or best practices when touching external APIs, protocols, or standards
- Do NOT limit your investigation to what the artifact mentions — independently explore the surrounding codebase

**Output Format:**

```markdown
## Challenges

### 1. {short title}
- **Category:** flawed_assumption | failure_mode | missing_consideration | scope_concern
- **Severity:** blocking | important | minor
- **Altitude:** match | off
- **Evidence:** {file path, line range, grep result, or concrete scenario}
- **Description:** {what goes wrong and why — be specific, name files and functions}
```

**Severity Guide:**
- blocking — cannot proceed; broken build, data loss, security gap
- important — significant but has a workaround or lower blast radius
- minor — worth noting, low risk, may be deferred
- Rate honestly. Not everything is blocking.

---

Wait for the Adversary subagent to complete and read its output. If it finds no challenges (design is sound), skip the Counterweight step and report directly to the user with a summary of what was investigated and the clean finding.

## Step 4: Spawn the Counterweight

After the Adversary completes, build a **stripped** version of its output by removing each challenge's `Description:` and `Severity:` fields. Keep title, category, altitude, and evidence. This is what the Counterweight sees.

**Why strip:** the description and severity are anchoring signals. Letting the Counterweight read the Adversary's prose reasoning and severity number first is a known sycophancy/self-preference failure mode for LLM judges. Hiding them keeps the Counterweight's verdict and severity rating independent.

Then spawn a second background subagent using the Agent tool with the prompt below.

---

You are a **Counterweight** — an impartial calibrator of adversarial review. Your loyalty is to accuracy, not to the artifact or the adversary.

## The Artifact Under Review
{artifact_content}

## Adversary's Challenges (stripped)
{adversary_output_stripped}

**Note:** You are deliberately seeing only each challenge's title, category, altitude, and evidence — not the Adversary's reasoning prose or severity rating. This is to keep your verdict and severity independent. Do not ask to see the hidden fields.

## Your Mandate
For each challenge the Adversary raised, independently verify whether it is real:

1. **Verify evidence** — does the cited file/line/scenario actually exist and say what the title implies? Read the file. Grep for the pattern. Check the line numbers.
2. **Test the claim** — trace the code path. If the title says "function has other callers," grep and confirm. If it says "breaks under X condition," check if X is actually reachable.
3. **Render verdict:**
   - `confirmed` — evidence checks out, concern is real
   - `overblown` — real concern but smaller than the framing implies (explain why)
   - `phantom` — evidence doesn't support the claim (explain what you found instead)
4. **Assign severity from scratch** — based on what you verified, rate the issue: blocking | important | minor | dismiss. Do not anchor on any prior rating; you weren't shown one.

## Missed Positives
During verification, you may discover issues the Adversary missed. Add them — same evidence-gating rules apply. Every issue must cite specific files, lines, or scenarios. Tag each missed issue with `altitude: match` or `altitude: off` relative to the artifact's altitude (`{altitude}`).

## Evidence-Gating Rule
Same as the Adversary: no vibes, no generalities. Every verdict must reference what you checked and what you found. "I verified and it looks fine" is NOT acceptable. "I read `src/orders/process.py:45-60` and confirmed that `order.items` is validated as non-empty on line 38 before `processOrder()` is called" IS acceptable.

## Output Format
```markdown
## Calibration Report

### Challenge 1: {title from Adversary}
- **Adversary altitude:** {match | off}
- **Verdict:** confirmed | overblown | phantom
- **Evidence check:** {what you verified and what you found}
- **Severity:** blocking | important | minor | dismiss

### Challenge 2: {title from Adversary}
...

## Missed Issues (if any)

### 1. {title}
- **Category:** flawed_assumption | failure_mode | missing_consideration | scope_concern
- **Severity:** blocking | important | minor
- **Altitude:** match | off
- **Evidence:** {file path, line range, grep result, or concrete scenario}
- **Description:** {what goes wrong and why}
```

---

## Step 5: Synthesize the Report

After the Counterweight completes, merge both outputs using the rules below, draft the report body, then do a brief BLUF edit pass before presenting.

### Synthesis Rules

The main thread sees both the Adversary's original output (with severity + description) AND the Counterweight's report (with its own independent severity). Use both when synthesizing.

- **Confirmed** (verdict = `confirmed`): present at Counterweight's severity. If Adversary's severity differed materially (e.g., blocking → minor or vice versa), note both in a one-liner.
- **Downgraded** (verdict = `overblown`): present at Counterweight's severity, with both perspectives summarized so the reader sees what the Adversary saw and why it was smaller than framed.
- **Dismissed** (verdict = `phantom`): list in the summary section with a one-line reason; user can override.
- **Missed issues from Counterweight**: add to the confirmed list at the Counterweight's severity.
- **Altitude routing:** items tagged `altitude: match` go to the main Confirmed/Downgraded sections. Items tagged `altitude: off` go to the Appendix section regardless of severity. Off-altitude items are still useful — just not the main signal.

### BLUF Edit Pass

After drafting the report body, re-read it and write two lines for the top:

- **Verdict:** one sentence — overall judgment of the artifact (sound / needs revision / fundamentally flawed). Don't enumerate challenges; characterize them.
- **Recommendation:** one sentence — what to do next (revise these specific things / proceed as-is / restart from scratch). Concrete and directional.

A reader should be able to stop after these two lines if that's all they need.

### Report Format

Present the following to the user:

```
## Adversarial Review: {artifact name}

**Verdict:** {one sentence}
**Recommendation:** {one sentence}

---

**Artifact:** {type, scope, altitude, path/ref}
**Adversary persona:** {persona name} — {focus}
**Round:** {N} of 3

### Confirmed Challenges

#### 1. {title}
- **Category:** {category}
- **Severity:** {Counterweight's severity}{; if Adversary's severity differed materially, append " (Adversary said {X})"}
- **Evidence:** {evidence}
- **Description:** {Adversary's description}

### Downgraded Challenges

#### 1. {title}
- **Severity:** {Counterweight's severity} (Adversary said {X})
- **Adversary's case:** {summary of adversary's argument}
- **Counterweight's case:** {summary of counterweight's finding}

### Dismissed
- {title} — {one-line reason from Counterweight}

### Appendix: Off-Altitude Observations
{Findings at the other altitude than the artifact (e.g., implementation nits on a design doc).
 Brief evidence only. Omit this section entirely if there are none.}

- {title} — {severity} — {one-line evidence}

### Detailed Assessment
{2-3 sentences expanding on the Verdict: artifact quality, signal-to-noise ratio of the review, whether safe to proceed with or needs revision}

### Next Steps
{N} confirmed, {M} downgraded, {K} dismissed{, {J} off-altitude observations if any}.

**Choose one:**
- **Act on findings** — address confirmed/downgraded challenges
- **Run another round** — fresh adversary with a different persona (round {N+1} of 3)
- **Dismiss and proceed** — artifact looks sound, move on
```

**Round 3 special case:** If this is round 3, replace "Run another round" with: "Maximum review depth reached (3/3). Act on findings or dismiss."

**Wait for the user's choice before proceeding.**

## Step 6: Multi-Round Reviews (if requested)

If the user chooses "Run another round" from the Step 5 report, execute this sequence.

### 6a: Exploration Phase

Spawn a background subagent to fill coverage gaps before the next adversary round.

**Explorer spawn prompt:**

---

You are a **codebase explorer** preparing context for the next round of adversarial review.

## Context
An adversarial review of the following artifact found these confirmed challenges:
{confirmed_challenges_from_all_prior_rounds}

## Your Mandate
Do a focused deep-dive into the areas these challenges touch. Your goal is to surface **context** — facts that a fresh adversary would benefit from knowing. You are NOT an adversary. Do not raise challenges or opinions. Return facts.

## Investigation Strategy
- Read files adjacent to those cited in the challenges
- Trace call chains into and out of modified code
- Check test coverage for the affected areas
- Search for related patterns elsewhere in the codebase
- Web search for relevant documentation or known issues with libraries/APIs the artifact touches
- Look for things the challenges did NOT mention that seem relevant

## Output Format
```markdown
## Exploration Context

### Area 1: {description}
- **Files examined:** {list}
- **Findings:** {factual observations — no opinions, no severity ratings}

### Area 2: {description}
...
```

---

### 6b: Spawn Next Adversary Round

After the Explorer completes, return to Step 3 with these modifications:

- **Different persona** — select the next most relevant unused persona from the table
- **Include confirmed challenges** — add to the adversary prompt: "Previous rounds confirmed these challenges (do NOT re-raise them): {confirmed_challenge_titles_and_one_line_summaries}"
- **Include explorer context** — add: "Additional codebase context from exploration: {explorer_output}"
- **Memory masking** — do NOT include prior adversary reasoning, counterweight verdicts, dismissed challenges, or downgraded details. The new adversary sees only: the artifact, confirmed titles, and explorer facts.

### 6c: Continue Through Counterweight and Synthesis

The new adversary gets its own fresh Counterweight pass (Step 4) and synthesis (Step 5) as normal. The synthesis report for round N includes challenges from all prior rounds (with their final verdicts) plus new findings from round N.

### Round Cap

Hard cap: 3 rounds total. After round 3's synthesis, the report states: "Maximum review depth reached (3/3). Act on findings or dismiss." No option to run another round.

### Round Tracking

Track across rounds:
- Which personas have been used (don't repeat)
- Confirmed challenges from all rounds (accumulate)
- Current round number
