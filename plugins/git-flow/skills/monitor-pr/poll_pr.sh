#!/usr/bin/env bash
# poll_pr.sh — block until PR state changes, then report what changed.
# Runs as a background Bash task; Claude reacts to <task-notification>.
#
# Usage: poll_pr.sh <owner/repo> <pr_number> <poll_interval_secs> [max_wait_secs]
#
# Environment:
#   PR_REVIEWER_BOTS — comma-separated bot logins whose verdicts gate exit.
#                      Defaults to "claude[bot]".
#                      Example: "claude[bot],my-project-reviewer[bot]"
#
# Self-initializing: gathers its own baseline on startup, then polls for
# changes. No external state file needed — avoids sandbox path issues
# between foreground and background Bash processes.
#
# Loops until a change is detected — does NOT exit on a timer. The
# optional max_wait_secs (default: 3600) is a safety net to prevent
# orphaned processes, not a normal exit path.

set -euo pipefail

REPO="$1"
PR="$2"
POLL_INTERVAL="${3:-60}"
MAX_WAIT="${4:-3600}"

# Build a jq selector expression from the configured bot list.
# Result looks like: .user.login == "claude[bot]" or .user.login == "other[bot]"
BOTS="${PR_REVIEWER_BOTS:-claude[bot]}"
BOT_FILTER=$(echo "$BOTS" | tr ',' '\n' | awk 'NF { printf "%s.user.login == \"%s\"", (n++ ? " or " : ""), $0 }')

# Gather baseline state
prev_review_ids=$(gh api "repos/${REPO}/pulls/${PR}/comments" --jq '[.[].id] | sort | join(",")' 2>/dev/null || echo "")
prev_issue_ids=$(gh api "repos/${REPO}/issues/${PR}/comments" --jq '[.[].id] | sort | join(",")' 2>/dev/null || echo "")
# Use JSON for checks so we can reason about pending vs fail vs pass per check,
# not just regrep on the rendered text (which counts pending as "all passing").
prev_checks=$(gh pr checks "$PR" --repo "$REPO" --json name,state,bucket,link 2>/dev/null \
  | jq -c 'sort_by(.name)' 2>/dev/null || echo "[]")
# jq + empty stdin produces empty stdout with exit 0, so `|| echo "[]"` doesn't fire;
# normalize explicitly so downstream counters never see "" (which bash arithmetic treats as 0).
[[ -z "$prev_checks" ]] && prev_checks="[]"
pr_json=$(gh pr view "$PR" --repo "$REPO" --json reviewDecision,state 2>/dev/null || echo "{}")
prev_decision=$(echo "$pr_json" | jq -r '.reviewDecision // ""')
prev_state=$(echo "$pr_json" | jq -r '.state // "OPEN"')
prev_bot_reviews=$(gh api "repos/${REPO}/pulls/${PR}/reviews" --jq "[.[] | select($BOT_FILTER) | {user: .user.login, state: .state}] | sort_by(.user) | tostring" 2>/dev/null || echo "[]")
# Bot reviewers may also post verdicts as issue comments (sticky comment pattern).
# Track the latest bot comment body to detect verdict changes.
prev_bot_comment=$(gh api "repos/${REPO}/issues/${PR}/comments" --jq "[.[] | select($BOT_FILTER)] | last | .body // \"\"" 2>/dev/null || echo "")

elapsed=0
while (( elapsed < MAX_WAIT )); do
  sleep "$POLL_INTERVAL"
  elapsed=$(( elapsed + POLL_INTERVAL ))

  # Gather current state
  cur_review_ids=$(gh api "repos/${REPO}/pulls/${PR}/comments" --jq '[.[].id] | sort | join(",")' 2>/dev/null || echo "")
  cur_issue_ids=$(gh api "repos/${REPO}/issues/${PR}/comments" --jq '[.[].id] | sort | join(",")' 2>/dev/null || echo "")
  cur_checks=$(gh pr checks "$PR" --repo "$REPO" --json name,state,bucket,link 2>/dev/null \
    | jq -c 'sort_by(.name)' 2>/dev/null || echo "[]")
  [[ -z "$cur_checks" ]] && cur_checks="[]"
  pr_json=$(gh pr view "$PR" --repo "$REPO" --json reviewDecision,state 2>/dev/null || echo "{}")
  cur_decision=$(echo "$pr_json" | jq -r '.reviewDecision // ""')
  cur_state=$(echo "$pr_json" | jq -r '.state // "OPEN"')
  cur_bot_reviews=$(gh api "repos/${REPO}/pulls/${PR}/reviews" --jq "[.[] | select($BOT_FILTER) | {user: .user.login, state: .state}] | sort_by(.user) | tostring" 2>/dev/null || echo "[]")
  cur_bot_comment=$(gh api "repos/${REPO}/issues/${PR}/comments" --jq "[.[] | select($BOT_FILTER)] | last | .body // \"\"" 2>/dev/null || echo "")

  changes=""

  # Compare bot review status (formal PR reviews)
  if [[ "$cur_bot_reviews" != "$prev_bot_reviews" ]]; then
    changes+="BOT_REVIEW_CHANGED\n$cur_bot_reviews\n"
  fi

  # Compare bot review status (issue comment verdicts — sticky comment pattern)
  if [[ "$cur_bot_comment" != "$prev_bot_comment" ]]; then
    # Extract verdict from comment body (look for emoji markers)
    bot_verdict=""
    if echo "$cur_bot_comment" | grep -q "✅"; then
      # Even on APPROVE, the bot can flag findings the body says belong in
      # this PR. Common convention across reviewer-bot stickies:
      # top-level severity headings (`### Critical`, `### High`, `### Medium`)
      # mean "fix this here or as a same-day follow-up"; Minors are collapsed
      # under `<details>` and are explicitly OK to defer. If the body has any
      # top-level Critical/High/Medium heading outside a <details> block, emit
      # APPROVED_WITH_FINDINGS:<csv> so the caller doesn't exit prematurely.
      findings=$(echo "$cur_bot_comment" | python3 -c '
import re, sys
body = sys.stdin.read()
# Strip <details>...</details> blocks (non-greedy, dot matches newlines).
stripped = re.sub(r"<details>.*?</details>", "", body, flags=re.DOTALL)
# Look for top-level severity headings. Match `### Medium` / `### Critical`
# / `### High` at the start of a line, optionally followed by trailing
# qualifiers (e.g. `### Medium — one MEDIUM gap in the new linter`).
hits = re.findall(r"^### (Critical|High|Medium)\b", stripped, flags=re.MULTILINE)
if hits:
    # De-duplicate while preserving order
    seen = []
    for h in hits:
        if h not in seen:
            seen.append(h)
    print(",".join(seen))
' 2>/dev/null || echo "")
      if [[ -n "$findings" ]]; then
        bot_verdict="APPROVED_WITH_FINDINGS:$findings"
      else
        bot_verdict="APPROVED"
      fi
    elif echo "$cur_bot_comment" | grep -q "🧌"; then
      bot_verdict="CHANGES_REQUESTED"
    fi
    prev_bot_comment="$cur_bot_comment"
    # Only wake up Claude when there's a final verdict, not for "working..." placeholder updates
    if [[ -n "$bot_verdict" ]]; then
      changes+="BOT_COMMENT_REVIEW_CHANGED\nVerdict: $bot_verdict\n"
    fi
  fi

  # Compare review comments
  if [[ "$cur_review_ids" != "$prev_review_ids" ]]; then
    new_ids=""
    IFS=',' read -ra CUR_ARR <<< "$cur_review_ids"
    IFS=',' read -ra PREV_ARR <<< "$prev_review_ids"
    for cid in "${CUR_ARR[@]}"; do
      found=0
      for pid in "${PREV_ARR[@]}"; do
        [[ "$cid" == "$pid" ]] && found=1 && break
      done
      [[ $found -eq 0 && -n "$cid" ]] && new_ids="$new_ids $cid"
    done

    if [[ -n "$new_ids" ]]; then
      changes+="NEW_REVIEW_COMMENTS\n"
      for nid in $new_ids; do
        comment_json=$(gh api "repos/${REPO}/pulls/comments/${nid}" --jq '{id, user: .user.login, path, line: .original_line, body}' 2>/dev/null || echo "{}")
        changes+="$comment_json\n"
      done
    fi
  fi

  # Compare issue comments
  if [[ "$cur_issue_ids" != "$prev_issue_ids" ]]; then
    new_ids=""
    IFS=',' read -ra CUR_ARR <<< "$cur_issue_ids"
    IFS=',' read -ra PREV_ARR <<< "$prev_issue_ids"
    for cid in "${CUR_ARR[@]}"; do
      found=0
      for pid in "${PREV_ARR[@]}"; do
        [[ "$cid" == "$pid" ]] && found=1 && break
      done
      [[ $found -eq 0 && -n "$cid" ]] && new_ids="$new_ids $cid"
    done

    if [[ -n "$new_ids" ]]; then
      changes+="NEW_ISSUE_COMMENTS\n"
      for nid in $new_ids; do
        comment_json=$(gh api "repos/${REPO}/issues/comments/${nid}" --jq '{id, user: .user.login, body}' 2>/dev/null || echo "{}")
        changes+="$comment_json\n"
      done
    fi
  fi

  # Compare CI checks
  if [[ "$cur_checks" != "$prev_checks" ]]; then
    # Count buckets from JSON. `bucket` is gh's normalization:
    #   pass | fail | pending | skipping | cancel
    # Unknown/future buckets are treated as non-terminal — we only declare green
    # when every check is explicitly in pass or skip/cancel (see n_total gate below).
    n_total=$(echo "$cur_checks" | jq 'length' 2>/dev/null || echo 0)
    n_fail=$(echo "$cur_checks" | jq '[.[] | select(.bucket == "fail")] | length' 2>/dev/null || echo 0)
    n_pending=$(echo "$cur_checks" | jq '[.[] | select(.bucket == "pending")] | length' 2>/dev/null || echo 0)
    n_pass=$(echo "$cur_checks" | jq '[.[] | select(.bucket == "pass")] | length' 2>/dev/null || echo 0)
    n_skip=$(echo "$cur_checks" | jq '[.[] | select(.bucket == "skipping" or .bucket == "cancel")] | length' 2>/dev/null || echo 0)

    if (( n_fail > 0 )); then
      changes+="CI_FAILURES\n"
      changes+="State: pass=$n_pass pending=$n_pending fail=$n_fail skip/cancel=$n_skip\n"
      failed_names=$(echo "$cur_checks" | jq -r '[.[] | select(.bucket == "fail") | .name] | join(", ")' 2>/dev/null || echo "")
      changes+="Failed checks: $failed_names\n"
      # Get failed run logs
      failed_runs=$(gh run list --branch "$(gh pr view "$PR" --repo "$REPO" --json headRefName --jq '.headRefName')" \
        --repo "$REPO" --status failure --json databaseId,name -L 5 2>/dev/null || echo "[]")
      changes+="Failed runs: $failed_runs\n"
      for run_id in $(echo "$failed_runs" | jq -r '.[].databaseId' 2>/dev/null); do
        log_tail=$(gh run view "$run_id" --repo "$REPO" --log-failed 2>/dev/null | tail -100 || echo "(no logs)")
        changes+="--- Run $run_id logs ---\n$log_tail\n"
      done
    elif (( n_pending == 0 && (n_pass + n_skip) == n_total && n_total > 0 )); then
      prev_checks="$cur_checks"
      # Every check is explicitly pass or skip/cancel (no failures, no pending,
      # no unknown-bucket surprises). Wake up only if bot already approved.
      if echo "$cur_bot_reviews" | grep -q '"state":"APPROVED"' || \
         echo "$cur_bot_comment" | grep -q "✅"; then
        changes+="CI_STATUS_CHANGED\nAll checks passing (pass=$n_pass skip/cancel=$n_skip pending=0 fail=0).\n"
      fi
    else
      # Something changed but checks are still in flight. Don't claim green;
      # update baseline silently and keep polling.
      prev_checks="$cur_checks"
    fi
  fi

  # Compare review decision
  if [[ "$cur_decision" != "$prev_decision" ]]; then
    changes+="REVIEW_DECISION_CHANGED\nWas: $prev_decision, Now: $cur_decision\n"
  fi

  # Check PR state
  if [[ "$cur_state" != "$prev_state" ]]; then
    changes+="PR_STATE_CHANGED\nWas: $prev_state, Now: $cur_state\n"
  fi

  if [[ -n "$changes" ]]; then
    echo -e "$changes"
    exit 0
  fi
done

echo "TIMEOUT after ${MAX_WAIT}s with no changes detected"
