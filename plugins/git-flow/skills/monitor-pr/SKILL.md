---
name: monitor-pr
description: Monitor a PR for CI failures and reviewer comments, fix issues, and respond thoughtfully.
argument-hint: "[hint] — optional natural language hint, e.g. 'focus on API changes', 'skip CI'"
---

# Monitor PR

Monitor an open PR through CI and code review, fixing failures and addressing reviewer feedback in a loop until the PR is approved or the iteration cap is reached.

Uses **background process chaining** — a cheap bash script sleeps and polls `gh`, running in the background via `run_in_background`. Claude only wakes up on `<task-notification>`, spending zero tokens while waiting.

## Configuring Reviewer Bots

Set `PR_REVIEWER_BOTS` to a comma-separated list of bot login names whose approval gates exit. Defaults to `claude[bot]` if unset.

```bash
# Examples
export PR_REVIEWER_BOTS="claude[bot]"
export PR_REVIEWER_BOTS="claude[bot],my-project-reviewer[bot]"
```

The list is passed to `poll_pr.sh` and used wherever bot reviewers are checked below.

## Step 1: Detect the PR

```bash
gh pr view --json number,url,title,reviewDecision,state,reviewRequests,headRefName,reviews,latestReviews
```

If no PR exists on the current branch, tell the user and stop.

Record the PR number, URL, head branch, owner/repo, and current state.

### Identify Bot Reviewers

The primary reviewers are bots configured via `$PR_REVIEWER_BOTS` (default: `claude[bot]`). Their approval is the gate — required before exit.

**Bot reviewers post verdicts in two ways:**
1. **Formal PR reviews** — show up in `gh api repos/.../pulls/.../reviews` with states like `APPROVED`, `CHANGES_REQUESTED`
2. **Issue comments (sticky comment pattern)** — the bot edits a single comment on the PR with verdict markers: `✅` = approved, `🧌` = changes requested. These show up in `gh api repos/.../issues/.../comments`, NOT in the PR reviews API.

Check both sources. The issue comment pattern is common for `claude[bot]` action-based reviewers.

## Step 2: Record Initial State

Note the current PR state for your own reference (comment counts, CI status, review decision, bot reviewer status). You don't need to write a state file — `poll_pr.sh` is self-initializing and gathers its own baseline on startup.

## Step 3: Parse Hint Argument

If the user provided a hint, interpret it semantically. Examples:
- "focus on API changes" — prioritize comments on API-related files
- "skip CI" — don't attempt CI fixes, only address reviewer comments
- "just watch" — report status but don't make changes

## Step 4: Enter the Main Loop

Initialize: `cycle = 0`, `max_cycles = 20`

### Starting a Poll (every cycle)

Launch `poll_pr.sh` in the background using the Bash tool with `run_in_background: true`:

```bash
/path/to/monitor-pr/poll_pr.sh "owner/repo" 42 <poll_interval_secs> [max_wait_secs]
```

The script is self-initializing — it gathers its own baseline state via `gh` API calls on startup, then loops with `sleep <poll_interval_secs>` until a change is detected. It does NOT exit on a timer. The optional `max_wait_secs` (default: 3600) is a safety net for orphaned processes, not a normal exit path.

Then **idle** — do nothing until `<task-notification>` fires. Do NOT poll, sleep, or check the task output proactively. Claude spends zero tokens while the script sleeps.

### Poll Interval

| Cycle | poll_interval_secs |
|-------|-------------------|
| 0 (initial) | 300 |
| 1 | 180 |
| 2+ | 60 |

### When `<task-notification>` Fires

The script only exits when something changed (or on safety timeout). So every notification means there's work to do.

1. **Read the task output** — this is the poll result.
2. **Check exit conditions first** (see Exit Conditions below).
3. **If "TIMEOUT"** — re-chain immediately (same cycle, don't increment).
4. **If changes detected** — triage and act:
   - `BOT_REVIEW_CHANGED` → fetch the full review comments, go to Addressing Comments. If state is `APPROVED`, also fetch the latest sticky comment and apply the same "top-level Medium+ findings?" check described under `BOT_COMMENT_REVIEW_CHANGED` below before treating this as a clean approve.
   - `BOT_COMMENT_REVIEW_CHANGED` → the bot updated its sticky comment verdict:
     - `Verdict: APPROVED` → clean approve, no unresolved Medium-or-higher findings. Check exit conditions.
     - `Verdict: APPROVED_WITH_FINDINGS:<severities>` → the bot approved overall but flagged one or more top-level Critical/High/Medium findings in the body. **This is NOT an exit condition** — fetch the full comment body (`gh api repos/{owner}/{repo}/issues/{number}/comments --jq '.[-1].body'`) and address the listed-severity findings like any other review comment. The convention is that top-level severity headings (`### Medium`, `### High`, `### Critical`) mean "fix this in this PR or as a same-day follow-up"; Minors under `<details>` are explicitly OK to defer.
     - `Verdict: CHANGES_REQUESTED` → fetch the full comment body and address the feedback.
   - `CI_FAILURES` → go to CI Failure Handling
   - `NEW_REVIEW_COMMENTS` or `NEW_ISSUE_COMMENTS` → go to Addressing Comments
   - `CI_STATUS_CHANGED` (all passing) → note it, check exit conditions
   - `REVIEW_DECISION_CHANGED` → check exit conditions
   - `PR_STATE_CHANGED` → check exit conditions
5. **After acting** — push, increment cycle, report to user, then re-chain.

### Re-chain (MANDATORY)

**Every notification handler MUST end by launching the next poll, unless an exit condition was met.** This is the mechanism that keeps monitoring alive — if you skip it, monitoring silently dies.

Re-chain = launch `poll_pr.sh` again with `run_in_background: true`, using the poll interval for the current cycle:

```bash
/path/to/monitor-pr/poll_pr.sh "owner/repo" 42 <poll_interval_secs>
```

Then idle until the next `<task-notification>`. Never ask "should I keep monitoring?" — the user already opted in.

## Exit Conditions

Stop the loop and announce the result when:

- **Bot reviewers cleanly approved + CI green**: All bots in `$PR_REVIEWER_BOTS` have approved AND there are no top-level Critical/High/Medium findings in their latest sticky comment (see "What counts as a clean approve" below) AND all CI checks pass. "No reviewers requested" is NOT an exit condition — if no bot review exists yet, keep waiting.
- **Iteration cap**: Cycle count reaches 20. Report current status (what's still pending).
- **PR closed/merged**: Someone closed or merged the PR externally. Announce and stop.

### What counts as a clean approve

The bot's sticky comment can carry both a top-level verdict AND findings. The verdict alone is not enough — read the body.

**Bot convention** (commonly observed across reviewer-bot stickies):

| Body shape | Means | Counts as clean approve? |
|---|---|---|
| `### ✅ Approve` + body has zero `### Medium` / `### High` / `### Critical` outside `<details>` blocks | Clean approve | ✅ Yes |
| `### ✅ Approve` + body has `<details><summary>Minor</summary>…</details>` | Approved with minors (deferrable) | ✅ Yes |
| `### ✅ Approve` + body has a top-level `### Medium`, `### High`, or `### Critical` heading | Approved overall, BUT the bot wants the listed-severity items fixed in this PR or as a same-day follow-up | ❌ **No — keep going** |
| `### 🧌 Request changes` (any body) | Not approved | ❌ No |

The `poll_pr.sh` script encodes this rule and emits `APPROVED_WITH_FINDINGS:<severities>` instead of `APPROVED` when the body has top-level severity findings. If you ever read a sticky directly (e.g. from `BOT_REVIEW_CHANGED` with formal-review state `APPROVED`), apply the same check yourself before declaring exit-ready: strip `<details>...</details>` blocks, then grep for `^### (Critical|High|Medium)\b`.

This rule exists because the bot uses APPROVE+Medium-in-body to mean "I'd merge this, but please address X first or same-day." Treating it as a clean approve and exiting silently misses real work the reviewer wants done.

### Checking Bot Reviewer Status

Bot reviewers may post verdicts via **formal PR reviews** or **issue comments** (sticky comment pattern). Check both.

Build the bot login filter from `$PR_REVIEWER_BOTS`:

```bash
# Construct a jq `or` expression: .user.login == "a" or .user.login == "b" ...
bots="${PR_REVIEWER_BOTS:-claude[bot]}"
bot_filter=$(echo "$bots" | tr ',' '\n' | awk '{printf "%s.user.login == \"%s\"", (NR>1?" or ":""), $0}')
```

**Formal PR reviews:**
```bash
gh api repos/{owner}/{repo}/pulls/{number}/reviews \
  --jq "[.[] | select($bot_filter) | {user: .user.login, state: .state}]"
```

Possible states: `APPROVED`, `CHANGES_REQUESTED`, `COMMENTED`, `PENDING`. Only `APPROVED` from all configured bot reviewers satisfies the exit condition.

**Issue comment verdicts (sticky comment pattern):**
```bash
gh api repos/{owner}/{repo}/issues/{number}/comments \
  --jq "[.[] | select($bot_filter)] | last | .body"
```

The bot edits a single sticky comment with its verdict. Look for emoji markers in the comment body:
- `✅` = approved (equivalent to `APPROVED`)
- `🧌` = changes requested (equivalent to `CHANGES_REQUESTED`)

Either source counts. The bot is satisfied **only when**:
1. The formal review says `APPROVED` OR the sticky comment contains `✅`, AND
2. The sticky comment body has no top-level `### Critical` / `### High` / `### Medium` heading outside a `<details>` block.

`poll_pr.sh` checks both — when it would have emitted `APPROVED` based on `✅` alone but the body has top-level Medium+ headings, it emits `APPROVED_WITH_FINDINGS:<severities>` instead. See "What counts as a clean approve" above for the full rule.

## CI Failure Handling

### 1. Identify Failures

The poll output includes failed run IDs and log tails. Read them.

### 2. Triage

- **Real failure from our changes** → fix it
- **Flaky test** (intermittent, unrelated to our changes) → note it, skip it
- **Infrastructure/environment issue** → note it, skip it

To distinguish flaky from real: check if the failing test touches code we changed. If not, likely flaky.

### 3. Fix Real Failures

- Read the relevant source files to understand the failure
- Make the fix
- **One commit per fix** with a descriptive message:
  ```
  Fix: missing import in UserService after extracting helper
  ```
- If a fix is non-obvious, explain the approach in the commit message body

## Addressing Reviewer Comments

CRITICAL: Evaluate every comment on its technical merits. Do not blindly implement suggestions. Do not performatively agree.

**Default bias: implement.** Minor suggestions (naming, small refactors, style improvements) should be implemented if they make the code better — think about what you'd wish you'd done a month from now. Only push back when a suggestion is actively harmful or introduces real complexity. "It's minor" is not a reason to skip it.

### For Each New Comment

**1. Read and understand the full context**
- Read the comment and the code it refers to
- Read the surrounding file for broader context
- Check if the comment is part of an existing thread

**2. Evaluate on its merits**
- Is the suggestion technically correct?
- Does it improve the code (readability, correctness, performance)?
- Does it introduce unnecessary complexity or over-engineering?
- Does it conflict with other reviewer feedback?

**3. Decide: implement, partially implement, or respectfully disagree**

| Severity | Default action |
|----------|---------------|
| Critical/High (bugs, security) | Always implement |
| Medium (design, maintainability) | Implement unless actively harmful |
| Minor (naming, style, small cleanup) | Implement — context is fresh now, cost is low |
| Disagree | Push back with reasoning (see below) |

### Implementing Feedback

- Fix the code
- **One commit per comment addressed**, with a message referencing the feedback:
  ```
  Address review: extract validation into helper per @reviewer
  ```
- Reply on the PR thread noting what was changed and in which commit:
  ```bash
  gh api repos/{owner}/{repo}/pulls/{number}/comments/{comment-id}/replies \
    -f body="Done — extracted into \`validateInput()\` in abc1234."
  ```

### Respectfully Disagreeing

Reply on the PR thread. The tone is two engineers working through a design together:

- Acknowledge the suggestion ("Good point about X...")
- Explain the reasoning for the current approach
- Note trade-offs considered
- Invite continued discussion ("What do you think?" / "Happy to reconsider if you see a case I'm missing")

```bash
gh api repos/{owner}/{repo}/pulls/{number}/comments/{comment-id}/replies \
  -f body="Good catch — I considered that approach but went with X because [reason]. The trade-off is [trade-off]. Happy to reconsider if you think [alternative] handles [edge case] better — what do you think?"
```

Never reply with "I won't do this" or dismiss the feedback.

### Replying to Issue-Level Comments

For comments on the PR itself (not inline on code):

```bash
gh pr comment {number} --body "..."
```

## After Each Cycle

After pushing, briefly report to the user what was done this cycle:
- Which CI failures were fixed (or skipped as flaky)
- Which reviewer comments were addressed or responded to
- Current PR status (CI, review decision)
- Cycle count / max

## Commit Strategy

- **One commit per fix** — separate commits for each CI fix and each reviewer comment
- Descriptive messages referencing the specific issue or reviewer
- **Single push** at the end of each cycle after all commits are made:
  ```bash
  git push
  ```

## Design Note

The poll script is self-initializing — it gathers baseline state via `gh` API on startup, then polls for changes. This avoids sharing state files between foreground and background Bash processes, which fails because `run_in_background` tasks run in a sandboxed `/tmp`.
