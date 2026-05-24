---
name: pr
description: Commit, push, and open a PR with a compelling title. Use when the user says "pr", "open a pr", "push and create pr", "commit and pr", wants to ship their branch, or before running "gh pr create".
---

# Commit, Push, and Open a PR

## Step 1: Understand the Full Branch

The user may have already committed everything. Run these in parallel to see the full picture:

```bash
git status
git log origin/main..HEAD --oneline
git diff origin/main...HEAD --stat
git diff origin/main...HEAD
```

Use **three dots** (`...`) for `git diff` — this compares against the merge-base, avoiding unrelated changes that landed on main after branching.

If there are uncommitted changes, stage and commit them first with an appropriate message.

## Step 2: Push

Push the branch to origin:

```bash
git push -u origin HEAD
```

## Step 3: Write the PR Title

The PR title is often the only thing a reader sees — in a chat notification, an email digest, the PR list view. Write it to **hook the reader with "why"**, not just "what".

**Prefix with a category:**

| Prefix | Use for |
|--------|---------|
| Fix | Bug fixes, correcting broken behavior |
| Feat | New features, capabilities, integrations |
| Perf | User-visible performance — faster API responses, faster page loads, faster ingest. The end user must experience the speed-up. |
| DX | Developer experience — CI/CD improvements, test infrastructure, merge queue optimizations, tooling, docs, agent workflows |
| Ops | Infrastructure, deployments, security, monitoring, maintenance, cost reduction |
| Compound | Feeding learnings back into the system — updating CLAUDE.md, skills, hooks, or rules so future work is easier |
| Reliability | Preventing outages, adding guardrails, improving resilience |
| Refactor | Restructuring code without changing behavior to reduce future friction |

**Category edge cases (common mistakes):**
- **Perf ≠ faster CI/pipeline.** Skipping tests in merge queue, caching CI builds, speeding up E2E shards → **DX** or **Ops**, not Perf. Perf is reserved for things end users see: API latency, page load, query speed, ingest throughput.
- **Perf vs Reliability for indexes/queries:** If the index prevents timeouts or failures, use **Reliability**. If it makes an already-working query faster, use **Perf**.
- **DX vs Feat for internal tooling:** If the primary audience is developers/agents (CI workflows, investigation tools, review bots, chat dev notifications), use **DX** even if it feels like a "feature". Use **Feat** only when end users see the capability.
- **Fix vs Compound:** If something is broken (even in a skill or doc), it's a **Fix**. Compound is for proactive improvements — teaching agents patterns, codifying learnings.
- **Ops vs DX for CI changes:** Cost-driven changes (skip an expensive job to cut bill) → **Ops**. Speed/workflow-driven changes (cache builds, skip slow tests for faster iteration) → **DX**.

**Pattern:** `[Category]: [verb] [thing] [so that / because / to prevent / for]`

Examples:
- `Fix: Prevent bookmark crash from racing optimistic cache update`
- `Feat: Stream tool call activity during chat to eliminate dead time`
- `Perf: Stop scanning 300K index entries to display 37 thumbnails`
- `DX: Skip synthetic monitoring tests in merge queue` ← not Perf (no user sees this)
- `DX: Let any workflow or local dev trigger investigation pipeline` ← not Feat (audience is devs)
- `Ops: Skip visual-regression captures on merge queue builds to eliminate ~5,760 wasted runs/month` ← Ops because cost-driven
- `Reliability: Block load-balancer stickiness in CI after two production incidents`
- `Compound: Teach agents the two-phase CTE pattern to prevent disk-spilling JOINs`

**Style rules:**

1. **Lead with the problem, not the solution** — "Prevent audio spinner from getting stuck" beats "Replace fragile ref guard with cleanup flag"
2. **Include concrete impact when available** — metrics, durations, multipliers: "27s → fast", "5x", "33-min outage", "74% singleton labels"
3. **Keep it short** — one clause after the colon is ideal. Avoid em-dashes and parentheticals unless they carry data.
4. **Don't leak implementation** — "Stop scanning 300K index entries" is good; "Use two-phase CTE with deferred JOIN" is too much
5. **Subtitles are OK for multi-part or flavor** — use `--` to separate: `"Fix merge queue concurrency -- Stop entries from cancelling each other's deploy jobs"`. Also OK: `"Part 2: Don't Feel Broken"`. Use sparingly — only when it adds genuine context or personality.
6. **Parenthetical impact** — inject scope/severity inline when it helps the reader gauge urgency: `"(33-min outage)"`, `"(Eliminate 30K-91K row scans)"`, `"(~5,760 wasted runs/month)"`

Before generating the title, consult `references/title-examples.md` for tone and style calibration.

**Title generation process (do this internally, don't show the user):**

1. Generate 3 candidate **prefixes** (e.g., Fix, DX, Reliability) with a one-line rationale for each
2. Generate 3 candidate **title bodies** (the part after the colon)
3. Reason about which prefix × body combination best fits the change, applying the category edge cases and style rules above
4. Use the winning combination directly — do not ask the user to choose

## Step 4: Write the PR Body

Structure:

```
## Summary
- [1-3 bullet points covering what and why]

## Test plan
- [ ] [How to verify the change works]
```

**For Fix PRs**, lead with the problem, not the solution:
1. **What's broken** — the bug and how it manifests
2. **Why it happens** — root cause
3. **What this PR does** — the fix and why this approach

Don't start with "Replace X with Y". Start with the symptom the reader can picture.

## Step 5: Linked Issues

If the work was motivated by an error tracker (Sentry, Honeybadger) issue or GitHub issue, include a link (e.g. `Closes #123`). Ask the user if you don't already know.

## Step 6: TBD Worktree Link

If working inside a [TBD](https://github.com/cheapsteak/tbd)-managed repo (path under `~/tbd/worktrees/`), append a copyable deep-link as the final line of the body so the matching worktree can be opened from the PR page.

Get the link — `TBD_WORKTREE_ID` is sometimes empty in Bash subshells, so try the env-var form first and fall back to the basename of the repo root, which TBD also accepts as a worktree identifier:

```bash
tbd link 2>/dev/null || tbd link "$(basename "$(git rev-parse --show-toplevel)")"
```

If that prints a `tbd://open?worktree=<uuid>` URL, take the `<uuid>` portion and emit the final line of the PR body as a markdown link to the GitHub Pages redirector:

```
[🔗 open in tbd](https://cheapsteak.github.io/tbd/open/?worktree=<uuid>)
```

**Why the redirector instead of a direct `tbd://` link.** GitHub sanitizes link hrefs to an http/https/mailto allowlist, so `[text](tbd://...)` renders with the href stripped — the text shows but isn't clickable. The `https://cheapsteak.github.io/tbd/open/` page is a tiny static redirector that reads `?worktree=` and bounces the browser to `tbd://open?worktree=<uuid>`. GitHub keeps the https anchor intact, the click round-trips through Pages, and macOS prompts to launch TBD.

This **replaces** any plain `worktree: <name>` footer the harness asks for — the URL already contains the worktree ID. If both `tbd link` invocations fail (not a TBD worktree, or TBD app not installed), skip this step and let the harness's plain-text footer stand.

Background: the `tbd://` URL scheme is registered by the TBD app — see cheapsteak/tbd#76 (URL handler + `tbd link` CLI) and cheapsteak/tbd#79 (system-prompt surfacing).

## Step 7: Create the PR

```bash
gh pr create --title "the pr title" --body "$(cat <<'EOF'
...body...
EOF
)"
```

Return the PR URL when done.

## Step 8: Monitor the PR

After the PR is created, automatically invoke the `monitor-pr` skill to watch for CI failures and bot reviewer feedback. Do not ask — this is the default.
