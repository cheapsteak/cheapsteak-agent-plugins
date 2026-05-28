# Title:   Wait for an HTTP endpoint to return a specific status code
# Args:    URL [EXPECTED_STATUS]    default: 200
# Example: run-recipe.sh recipes/wait-for-http-ready.recipe.sh \
#            https://api.example.com/health 200
#
# Connection refused / DNS failure / timeout all return "000" — the loop keeps
# polling rather than aborting. Use this for service-up checks, deploy verify,
# or "wait for endpoint to exist before polling its JSON" preflights.

URL="$1"
EXPECTED_STATUS="${2:-200}"

FETCH() {
  curl -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout 5 --max-time 10 "$URL" 2>/dev/null || echo "000"
}

EXTRACT() { cat; }

WAKE_WHEN() {
  [[ "$cur" == "$EXPECTED_STATUS" ]]
}

EMIT() {
  echo "URL=$URL"
  echo "HTTP_STATUS=$cur"
}

POLL_EVERY=10
MAX_WAIT=600
TAG=HTTP_READY
