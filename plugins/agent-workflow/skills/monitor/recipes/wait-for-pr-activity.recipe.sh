# Title:   Wait for activity on a GitHub PR (comments, reviews, CI, state changes)
# Args:    OWNER/REPO PR_NUMBER
# Example: run-recipe.sh recipes/wait-for-pr-activity.recipe.sh \
#            cheapsteak/cheapsteak-agent-plugins 42
#
# Multi-signal recipe. Batches 5 gh-api calls into one JSON blob per tick;
# uses lib.sh helpers to per-signal diff inside EMIT. Watches:
#   - new issue comments
#   - new inline review comments (gh-api: pulls/{n}/comments)
#   - new formal reviews          (gh-api: pulls/{n}/reviews — APPROVED, CHANGES_REQUESTED, etc.)
#   - CI check failures           (gh pr checks --json bucket,name)
#   - review decision, PR state, mergeable, mergeStateStatus, isDraft, head SHA
#
# POLL_EVERY=60 minimum recommended — each tick fans out 5+ gh-api calls.

REPO="$1"
PR="$2"

FETCH() {
  # Every sub-fetch falls back to '[]' or '{}' on failure so jq -n --argjson never aborts.
  local issue_comments review_comments reviews checks state
  issue_comments="$(gh api "repos/$REPO/issues/$PR/comments"  --jq '[.[] | {id, user: .user.login, body}]'                            2>/dev/null || echo '[]')"
  review_comments="$(gh api "repos/$REPO/pulls/$PR/comments" --jq '[.[] | {id, user: .user.login, path, line: .original_line, body}]' 2>/dev/null || echo '[]')"
  reviews="$(gh api         "repos/$REPO/pulls/$PR/reviews"  --jq '[.[] | {id, user: .user.login, state, body}]'                     2>/dev/null || echo '[]')"
  checks="$(gh pr checks "$PR" --repo "$REPO" --json name,state,bucket 2>/dev/null | jq -c 'sort_by(.name)' || echo '[]')"
  [[ -z "$checks" ]] && checks='[]'
  state="$(gh pr view "$PR" --repo "$REPO" --json reviewDecision,state,mergeable,mergeStateStatus,isDraft,headRefOid 2>/dev/null || echo '{}')"

  jq -n \
    --argjson issue_comments  "$issue_comments" \
    --argjson review_comments "$review_comments" \
    --argjson reviews         "$reviews" \
    --argjson checks          "$checks" \
    --argjson state           "$state" \
    '{issue_comments: $issue_comments, review_comments: $review_comments, reviews: $reviews, checks: $checks, state: $state}'
}

EXTRACT() { cat; }

WAKE_WHEN() { [[ "$cur" != "$prev" ]]; }

EMIT() {
  diff_new_ids     NEW_ISSUE_COMMENTS  '.issue_comments'  '.id'
  diff_new_ids     NEW_REVIEW_COMMENTS '.review_comments' '.id'
  diff_new_ids     NEW_REVIEWS         '.reviews'         '.id'
  diff_bucket_fail CI_FAILURES         '.checks'
  diff_changed     REVIEW_DECISION     '.state.reviewDecision'
  diff_changed     PR_STATE            '.state.state'
  diff_changed     PR_MERGEABLE        '.state.mergeable'
  diff_changed     PR_MERGE_STATE      '.state.mergeStateStatus'
  diff_changed     PR_IS_DRAFT         '.state.isDraft'
  diff_changed     HEAD_SHA            '.state.headRefOid'
}

POLL_EVERY=60
MAX_WAIT=3600
TAG=PR
