# Title:   Wait for a GitHub Actions workflow run to reach a terminal state
# Args:    OWNER/REPO RUN_ID
# Example: run-recipe.sh recipes/wait-for-gh-run.recipe.sh \
#            cheapsteak/cheapsteak-agent-plugins 1234567890

REPO="$1"
RUN_ID="$2"

FETCH() {
  gh run view "$RUN_ID" --repo "$REPO" --json status,conclusion,url 2>/dev/null || echo '{}'
}

EXTRACT() {
  jq -c '{status, conclusion, url}'
}

WAKE_WHEN() {
  [[ "$(jq -r '.status // empty' <<< "$cur")" == "completed" ]]
}

EMIT() {
  echo "RUN_STATUS=$(jq    -r '.status     // ""' <<< "$cur")"
  echo "RUN_CONCLUSION=$(jq -r '.conclusion // ""' <<< "$cur")"
  echo "RUN_URL=$(jq        -r '.url        // ""' <<< "$cur")"
}

POLL_EVERY=30
MAX_WAIT=3600
TAG=GH_RUN
