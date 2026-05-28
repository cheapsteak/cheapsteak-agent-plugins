#!/usr/bin/env bash
# poll_pr.sh — block until PR state changes, then report what changed.
# Runs as a background Bash task; Claude reacts to <task-notification>.
#
# Usage: poll_pr.sh <owner/repo> <pr_number> <wait_secs> <max_polls>
#
# Self-initializing: gathers its own baseline on startup, then polls for
# changes. No external state file needed — avoids sandbox path issues
# between foreground and background Bash processes.
#
# Exits with output describing what changed. If nothing changed after
# max_polls, prints "No changes detected".

set -euo pipefail

REPO="$1"
PR="$2"
WAIT_SECS="${3:-60}"
MAX_POLLS="${4:-3}"

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

for (( poll=1; poll<=MAX_POLLS; poll++ )); do
  sleep "$WAIT_SECS"

  # Gather current state
  cur_review_ids=$(gh api "repos/${REPO}/pulls/${PR}/comments" --jq '[.[].id] | sort | join(",")' 2>/dev/null || echo "")
  cur_issue_ids=$(gh api "repos/${REPO}/issues/${PR}/comments" --jq '[.[].id] | sort | join(",")' 2>/dev/null || echo "")
  cur_checks=$(gh pr checks "$PR" --repo "$REPO" --json name,state,bucket,link 2>/dev/null \
    | jq -c 'sort_by(.name)' 2>/dev/null || echo "[]")
  [[ -z "$cur_checks" ]] && cur_checks="[]"
  pr_json=$(gh pr view "$PR" --repo "$REPO" --json reviewDecision,state 2>/dev/null || echo "{}")
  cur_decision=$(echo "$pr_json" | jq -r '.reviewDecision // ""')
  cur_state=$(echo "$pr_json" | jq -r '.state // "OPEN"')

  changes=""

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
      changes+="CI_STATUS_CHANGED\nAll checks passing (pass=$n_pass skip/cancel=$n_skip pending=0 fail=0).\n"
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

echo "No changes detected"
