---
name: monitor
description: >
  Create a background polling loop that monitors an external system and wakes Claude
  only when something changes. Use when the user says "monitor", "watch", "keep an eye on",
  "poll", "wait for", or wants to be notified when something external finishes or changes
  (CI, deployments, build jobs, API status, review approvals, etc.).
disable-model-invocation: true
argument-hint: "<what to monitor> — e.g. 'PR #42 CI and reviews', 'staging deploy', 'build job 123'"
---

# Monitor

Create a background polling loop that watches an external system and wakes Claude only when state changes. Spends zero tokens while waiting.

## How It Works

1. **You write a poll script** tailored to what needs monitoring
2. **Launch it in the background** via `Bash(run_in_background: true)`
3. **Idle** until `<task-notification>` fires
4. **React** to changes, then chain the next poll

The user opts in once. After that, re-chain polls silently — never ask "want me to keep monitoring?"

## Step 1: Understand What to Monitor

Ask (or infer from context):
- **What system?** (GitHub, GitLab, CI, deploy pipeline, API endpoint, job queue, etc.)
- **What constitutes a "change"?** (CI passes/fails, new comments, state transition, job completes)
- **What should Claude do when something changes?** (fix it, report it, take action)
- **When should monitoring stop?** (success condition, iteration cap, timeout)

## Step 2: Write the Poll Script

Write a bash script that:
1. **Gathers baseline state** on startup (self-initializing — see Design Constraints below)
2. **Sleeps** for the configured interval
3. **Re-checks state** and compares to baseline
4. **Exits with a summary** if something changed, or "No changes detected" after max polls

### Script Template

```bash
#!/usr/bin/env bash
# poll.sh — self-initializing poller for [system].
# Usage: poll.sh <wait_secs> <max_polls> [extra args...]
set -euo pipefail

WAIT_SECS="${1:-60}"
MAX_POLLS="${2:-3}"

# === BASELINE: gather initial state ===
prev_status=$( <command to check current state> )

for (( poll=1; poll<=MAX_POLLS; poll++ )); do
  sleep "$WAIT_SECS"

  # === CHECK: gather current state ===
  cur_status=$( <same command> )

  changes=""

  if [[ "$cur_status" != "$prev_status" ]]; then
    changes+="STATUS_CHANGED\nWas: $prev_status\nNow: $cur_status\n"
  fi

  if [[ -n "$changes" ]]; then
    echo -e "$changes"
    exit 0
  fi
done

echo "No changes detected"
```

Adapt the template for the specific system. The script should output structured, parseable text — use tags like `CI_FAILURES`, `NEW_COMMENTS`, `STATUS_CHANGED`, `JOB_COMPLETE` so Claude can triage programmatically.

### Wait Schedule

Scale the interval to the expected response time:

| Situation | wait_secs | max_polls | Total wait |
|-----------|-----------|-----------|------------|
| Initial (CI just started) | 300 | 2 | ~10 min |
| Mid-cycle (some checks done) | 60-180 | 3 | 3-9 min |
| Fast checks (deploys, jobs) | 30 | 5 | ~2.5 min |

### Script Location

Write the script to the skill directory or a temp location accessible to background processes (see Design Constraints).

## Step 3: Launch the Loop

```bash
# Launch in background — Claude idles until <task-notification>
Bash(/path/to/poll.sh <wait_secs> <max_polls> [args...], run_in_background: true, timeout: 600000)
```

Set `timeout` to at least `wait_secs * max_polls + 60000` (buffer for API calls).

## Step 4: React to Changes

When `<task-notification>` fires:

1. **Read the output** — check what changed
2. **Check exit conditions** — is monitoring done? (success, failure, merged, closed, cap reached)
3. **If "No changes detected"** — chain the next poll immediately (same cycle)
4. **If changes detected** — triage and act:
   - Fix issues (CI failures, test errors)
   - Respond to feedback (reviewer comments)
   - Report status to user
5. **Chain next poll** after acting

### Exit Conditions

Stop when:
- **Goal achieved** (CI green + approved, deploy complete, job finished)
- **Iteration cap** reached (default: 20 cycles). Report what's still pending.
- **External closure** (PR merged, job cancelled, etc.)

### Cycle Counter

Track cycles to avoid infinite loops:
```
cycle = 0, max_cycles = 20
```
Increment after each action cycle. "No changes" re-chains don't increment.

## Design Constraints

### Self-Initializing Scripts (Critical)

**Never rely on state files shared between foreground and background processes.**

Background processes launched via `Bash(run_in_background: true)` run in a sandboxed environment. Files written to `/tmp` by a foreground Bash call are NOT accessible to background tasks. This means:

- A state file written by Claude in Step 2 will not exist when the background poll script reads it
- The script will fail with "file not found"

**The fix:** Make scripts self-initializing. The script gathers its own baseline state via API calls on startup, then polls for changes against that baseline. No external state file needed.

If you truly need shared state between cycles (rare), write it to the **project working directory** (which IS shared), not `/tmp`. But prefer self-initializing scripts.

### Timeout Budget

The Bash tool has a max timeout of 600,000ms (10 minutes). For longer monitoring:
- Use shorter poll intervals with re-chaining
- Each `<task-notification>` → new background launch gives you another 10 minutes
- Chain indefinitely via the cycle loop

### Token Efficiency

The entire point of this pattern is zero-token waiting. While the background script sleeps:
- Claude is idle (no polling, no sleeping, no checking)
- The user can do other work or send other messages
- Claude wakes ONLY on `<task-notification>`

Never use `sleep` in a foreground Bash call to wait for external state. Always use background polling.

## Reference: GitHub PR Monitor

See `references/poll-github-pr.sh` for a complete, production-tested example that monitors a GitHub PR for CI status changes, new review comments, and approval state changes.

Adapt this pattern for other systems:
- **GitLab**: Replace `gh` commands with `glab` or `curl` to GitLab API
- **CI/CD**: Poll `curl https://ci.example.com/api/builds/123` for status
- **Deploys**: Check `kubectl rollout status` or cloud provider APIs
- **Job queues**: Poll queue depth or specific job status endpoints
