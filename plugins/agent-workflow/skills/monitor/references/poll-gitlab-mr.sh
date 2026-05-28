#!/usr/bin/env bash
# poll-gitlab-mr.sh — monitor a GitLab merge request for pipeline and review changes.
# Self-initializing: gathers baseline on startup, no external state file needed.
#
# Usage: poll-gitlab-mr.sh <project_id_or_path> <mr_iid> <wait_secs> <max_polls>
#
# Requires: GITLAB_TOKEN env var (or glab CLI authenticated)
# Uses glab CLI (https://gitlab.com/gitlab-org/cli) if available, falls back to curl.
#
# Example:
#   export GITLAB_TOKEN="glpat-xxxx"
#   ./poll-gitlab-mr.sh mygroup/myproject 42 60 3

set -euo pipefail

PROJECT="$1"      # URL-encoded project path or numeric ID
MR_IID="$2"
WAIT_SECS="${3:-60}"
MAX_POLLS="${4:-3}"

# URL-encode project path for API calls (replace / with %2F)
PROJECT_ENC="${PROJECT//\//%2F}"
GITLAB_API="${GITLAB_API_URL:-https://gitlab.com}/api/v4"

api() {
  curl -sf -H "PRIVATE-TOKEN: ${GITLAB_TOKEN:-}" "$GITLAB_API/$1"
}

# === BASELINE ===
prev_pipeline=$(api "projects/${PROJECT_ENC}/merge_requests/${MR_IID}/pipelines" | jq -r '.[0] | "\(.id):\(.status)"' 2>/dev/null || echo "")
prev_notes=$(api "projects/${PROJECT_ENC}/merge_requests/${MR_IID}/notes?sort=asc" | jq -r '[.[].id] | sort | join(",")' 2>/dev/null || echo "")
prev_mr=$(api "projects/${PROJECT_ENC}/merge_requests/${MR_IID}" 2>/dev/null || echo "{}")
prev_state=$(echo "$prev_mr" | jq -r '.state // "opened"')
prev_approvals=$(api "projects/${PROJECT_ENC}/merge_requests/${MR_IID}/approvals" | jq -r '.approved_by | length' 2>/dev/null || echo "0")

for (( poll=1; poll<=MAX_POLLS; poll++ )); do
  sleep "$WAIT_SECS"

  cur_pipeline=$(api "projects/${PROJECT_ENC}/merge_requests/${MR_IID}/pipelines" | jq -r '.[0] | "\(.id):\(.status)"' 2>/dev/null || echo "")
  cur_notes=$(api "projects/${PROJECT_ENC}/merge_requests/${MR_IID}/notes?sort=asc" | jq -r '[.[].id] | sort | join(",")' 2>/dev/null || echo "")
  cur_mr=$(api "projects/${PROJECT_ENC}/merge_requests/${MR_IID}" 2>/dev/null || echo "{}")
  cur_state=$(echo "$cur_mr" | jq -r '.state // "opened"')
  cur_approvals=$(api "projects/${PROJECT_ENC}/merge_requests/${MR_IID}/approvals" | jq -r '.approved_by | length' 2>/dev/null || echo "0")

  changes=""

  # Pipeline status changed
  if [[ "$cur_pipeline" != "$prev_pipeline" ]]; then
    pipeline_status="${cur_pipeline#*:}"
    if [[ "$pipeline_status" == "failed" ]]; then
      pipeline_id="${cur_pipeline%%:*}"
      changes+="CI_FAILURES\n"
      # Get failed jobs
      failed_jobs=$(api "projects/${PROJECT_ENC}/pipelines/${pipeline_id}/jobs?scope[]=failed" | jq -r '.[] | "\(.name): \(.web_url)"' 2>/dev/null || echo "(no jobs)")
      changes+="Failed jobs:\n$failed_jobs\n"
      # Get job logs (first failed job)
      first_job_id=$(api "projects/${PROJECT_ENC}/pipelines/${pipeline_id}/jobs?scope[]=failed" | jq -r '.[0].id' 2>/dev/null || echo "")
      if [[ -n "$first_job_id" && "$first_job_id" != "null" ]]; then
        log_tail=$(api "projects/${PROJECT_ENC}/jobs/${first_job_id}/trace" 2>/dev/null | tail -100 || echo "(no logs)")
        changes+="--- Job $first_job_id logs ---\n$log_tail\n"
      fi
    elif [[ "$pipeline_status" == "success" ]]; then
      changes+="CI_STATUS_CHANGED\nPipeline passed.\n"
    else
      changes+="CI_STATUS_CHANGED\nPipeline status: $pipeline_status\n"
    fi
  fi

  # New discussion notes
  if [[ "$cur_notes" != "$prev_notes" ]]; then
    IFS=',' read -ra CUR_ARR <<< "$cur_notes"
    IFS=',' read -ra PREV_ARR <<< "$prev_notes"
    new_ids=""
    for cid in "${CUR_ARR[@]}"; do
      found=0
      for pid in "${PREV_ARR[@]}"; do
        [[ "$cid" == "$pid" ]] && found=1 && break
      done
      [[ $found -eq 0 && -n "$cid" ]] && new_ids="$new_ids $cid"
    done
    if [[ -n "$new_ids" ]]; then
      changes+="NEW_COMMENTS\n"
      for nid in $new_ids; do
        note=$(api "projects/${PROJECT_ENC}/merge_requests/${MR_IID}/notes/${nid}" | jq -r '{id, author: .author.username, body}' 2>/dev/null || echo "{}")
        changes+="$note\n"
      done
    fi
  fi

  # Approval count changed
  if [[ "$cur_approvals" != "$prev_approvals" ]]; then
    changes+="APPROVAL_CHANGED\nWas: $prev_approvals approvals, Now: $cur_approvals approvals\n"
  fi

  # MR state changed (opened -> merged, closed, etc.)
  if [[ "$cur_state" != "$prev_state" ]]; then
    changes+="MR_STATE_CHANGED\nWas: $prev_state, Now: $cur_state\n"
  fi

  if [[ -n "$changes" ]]; then
    echo -e "$changes"
    exit 0
  fi
done

echo "No changes detected"
