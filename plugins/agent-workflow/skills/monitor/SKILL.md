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

Background polling that wakes Claude only when state changes. Spends zero tokens while waiting.

You describe what to watch as a small **recipe** (4 bash functions + 3 env vars). A shared **runtime** (`run-recipe.sh`) handles the loop, baseline capture, polling, failure tolerance, and output discipline. The user opts in once; after that, re-chain polls silently — never ask "want me to keep monitoring?"

## The recipe DSL

A recipe is a bash blob with this contract:

```bash
FETCH()     { ...; }   # raw response on stdout
EXTRACT()   { ...; }   # stdin -> one value to diff/match on stdout
WAKE_WHEN() { ...; }   # predicate over $cur / $prev; exit 0 to wake, 1 to keep polling
EMIT()      { ...; }   # structured output when waking (line-oriented TAG_SUBKEY=value)

POLL_EVERY=30          # seconds between polls
MAX_WAIT=1800          # safety-net upper bound; loop exits with TIMEOUT
TAG=JOB                # short prefix printed as first line of wake payload
```

That's the entire surface. Each tick: runtime computes `cur=$( FETCH | EXTRACT )`, calls `WAKE_WHEN`; if 0 prints `TAG` then `EMIT`'s output and exits; else sets `prev=$cur` and waits `POLL_EVERY` seconds.

### Default invocation: inline heredoc (no file needed)

```bash
plugins/agent-workflow/skills/monitor/run-recipe.sh - <<'EOF'
FETCH()     { curl -sS "https://api.example.com/jobs/42"; }
EXTRACT()   { jq -r '.status // empty'; }
WAKE_WHEN() { [[ -n "$cur" && "$cur" =~ ^(success|failed)$ ]]; }
EMIT()      { echo "JOB_STATE=$cur"; }
POLL_EVERY=30 MAX_WAIT=1800 TAG=JOB
EOF
```

Launch in the background with `Bash(run_in_background: true)` and idle until `<task-notification>` fires. Quoted `'EOF'` disables shell expansion so the recipe body is verbatim.

### Alternative: file-based (for library recipes or anything reusable)

```bash
plugins/agent-workflow/skills/monitor/run-recipe.sh \
  recipes/wait-for-json-value.recipe.sh \
  https://api.example.com/jobs/42 '.status' '^(success|failed)$'
```

Positional args after the recipe path become `$1`, `$2`, … inside the recipe — capture them at the top of the recipe body (`URL="$1"; JQ_PATH="$2"; …`).

**Mental rule**: throwaway → heredoc; reusable → write or fork a library recipe.

## Contract rules

- **`WAKE_WHEN` exit code**: `0` wakes; `1` keeps polling. Always invoked as `if WAKE_WHEN; then`. Don't `&&`-chain anything else into the function — the regex test on the last line must be the function's exit status.
- **`EMIT` output shape**: line-oriented `TAG_SUBKEY=value`, one pair per line. Survives truncation, no escaping headaches, parseable without a JSON validator. Avoid raw JSON in `EMIT` unless it's the natural shape of the data (e.g. a list of new comment objects).
- **Stdout discipline**: exactly one of (`TAG` line + `EMIT` output), `TIMEOUT after <s>s`, or `FETCH_FAILED`. Stderr carries all debug noise (baseline capture log, fetch errors, signal handling). Exit code is `0` on every normal exit; non-zero only for setup errors (missing functions, missing env vars, bad recipe path).
- **Runtime hardening**: heredoc body is read into a tempfile before sourcing (avoids `/dev/stdin` quirks under `run_in_background`); transient `FETCH|EXTRACT` failures log and continue, five consecutive failures emit `FETCH_FAILED` and exit; `EXTRACT` output has trailing whitespace stripped (no spurious wake on layout noise); `trap` + interruptible sleep so `SIGTERM` exits within ~1s.

## Recipe library

Recipes live in `recipes/`. Each is a fork-starting-point — copy or compose with library recipes when an exact match doesn't exist.

| Recipe | Args | What it does |
|---|---|---|
| `wait-for-json-value.recipe.sh` | `URL JQ_PATH MATCH_REGEX` | Poll a JSON endpoint; wake when the extracted value matches the regex. Workhorse for REST APIs, status endpoints. Treats `null` / missing as "no value yet". Optional `CURL_OPTS` env for auth. |
| `wait-for-page-text.recipe.sh` | `URL PATTERN [MODE]` | Grep response body for `PATTERN`; wake on transition. `MODE` = `appears` (default) or `disappears`. `REGEX=1` env enables regex; default is fixed string. |
| `wait-for-http-ready.recipe.sh` | `URL [EXPECTED_STATUS]` | Wake when the endpoint returns `EXPECTED_STATUS` (default 200). Connection-refused / DNS / timeout return `"000"` — kept polling. Canonical service-up / deploy-verify recipe. |
| `wait-for-gh-run.recipe.sh` | `OWNER/REPO RUN_ID` | Wake when a GitHub Actions run reaches a terminal state. Emits `RUN_STATUS`, `RUN_CONCLUSION`, `RUN_URL`. |
| `wait-for-pr-activity.recipe.sh` | `OWNER/REPO PR_NUMBER` | Multi-signal. Watches issue comments, inline review comments, formal reviews, CI checks, review decision, PR state, mergeable, mergeStateStatus, isDraft, head SHA. Min `POLL_EVERY=60` (fans out 5+ gh-api calls per tick). |

## Multi-signal recipes

When you need to watch several things at once (the PR case), the contract bends slightly:

- `FETCH` produces a single JSON blob batching every signal (use `jq -n --argjson` with `|| echo '[]'` / `|| echo '{}'` defaults on every sub-fetch — without the fallback, a transient sub-call failure crashes `jq -n`).
- `EXTRACT` is `cat` (the blob *is* the value to diff).
- `WAKE_WHEN` is `[[ "$cur" != "$prev" ]]`.
- `EMIT` calls helpers from `lib.sh` to per-signal diff and emit tagged blocks.

`lib.sh` (sourced automatically by the runtime before the recipe) provides:

| Helper | Use when |
|---|---|
| `diff_changed TAG '<jq_path>'` | A scalar value (status, decision, sha) flipped between ticks. |
| `diff_new_ids TAG '<array_path>' '<id_jq>'` | An array gained new items (comments, reviews) — emits the new items as a JSON array. |
| `diff_bucket_fail TAG '<checks_path>'` | The set of items with `.bucket == "fail"` changed — emits failed names + pass/pending/fail/skip counts. Built for `gh pr checks --json bucket,name`. |

See `recipes/wait-for-pr-activity.recipe.sh` for the canonical multi-signal example.

## Writing a new recipe

Easiest path: copy the closest library recipe, edit `FETCH` / `EXTRACT` / `WAKE_WHEN`, run it.

For genuinely trivial cases the library doesn't cover (e.g. waiting for a local file to appear), write inline as a heredoc — five lines suffice:

```bash
plugins/agent-workflow/skills/monitor/run-recipe.sh - <<'EOF'
FETCH()     { [[ -f /tmp/build.done ]] && echo present || echo absent; }
EXTRACT()   { cat; }
WAKE_WHEN() { [[ "$cur" == present ]]; }
EMIT()      { echo "FILE=/tmp/build.done"; }
POLL_EVERY=5 MAX_WAIT=300 TAG=FILE_APPEARED
EOF
```

Recipe-author rules (learned the hard way):

- **`curl -sS`, not `curl -sSf`**: `-f` makes HTTP 5xx fatal. The runtime would log "FETCH failed" and degrade for a single 503, but if you write your own loop without the runtime you'd kill it. Reserve `-f` for cases where 5xx genuinely is fatal.
- **Treat `null` / missing as "no value yet"**: `jq -r '.path // empty'` returns nothing for missing keys or explicit `null`, and a WAKE_WHEN check guarded with `[[ -n "$cur" && ... ]]` won't fire on empty. Otherwise a permissive `MATCH_REGEX` (`.`) wakes spuriously on the literal string `"null"`.
- **Defensive defaults on every sub-fetch in multi-signal `FETCH`**: `gh api ... || echo '[]'` and `... || echo '{}'`. `jq -n --argjson` aborts on empty stdin.
- **Set a sane `POLL_EVERY` for multi-call recipes** — fanning out N API calls per tick burns rate limit fast. The shipped `wait-for-pr-activity.recipe.sh` sets 60s.

## Reacting to wake notifications

When `<task-notification>` fires:

1. Read the task output — the wake payload tells you what changed.
2. Check exit conditions (success, failure, merged, closed, iteration cap, etc.).
3. If `TIMEOUT` — re-chain immediately (same cycle).
4. If `FETCH_FAILED` — investigate (network down? auth expired? endpoint moved?).
5. Otherwise — triage by tag and act (fix CI failures, respond to reviewer comments, report status to user).
6. Re-chain next poll after acting (MANDATORY — every notification handler must launch the next poll unless an exit condition was met).

## References (legacy)

`references/poll-github-pr.sh` and `references/poll-gitlab-mr.sh` are hand-coded polling scripts predating the recipe DSL. Kept as starting points for cases where the recipe model doesn't fit. For anything new, prefer the DSL.

## Why this pattern is token-efficient

While the background script sleeps, Claude is idle — no polling, no checking, no foreground `sleep`. Claude wakes ONLY on `<task-notification>`. The Bash tool's 10-minute timeout doesn't matter: each notification → new background launch gives you another 10 minutes; chain indefinitely.

Never use foreground `sleep` to wait for external state — that burns tokens for nothing. Always use the recipe runtime.
