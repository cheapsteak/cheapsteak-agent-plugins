# Title:   Wait for a JSON value at a URL to match a regex
# Args:    URL JQ_PATH MATCH_REGEX
# Example: run-recipe.sh recipes/wait-for-json-value.recipe.sh \
#            https://api.example.com/jobs/42 .status '^(success|failed)$'
# Env:     CURL_OPTS — optional extra flags for curl (auth headers, cookies, etc.)
#
# Treats explicit JSON null and missing paths as "no value yet" — does not wake
# even if MATCH_REGEX is permissive (e.g. ".").

URL="$1"
JQ_PATH="$2"
MATCH_REGEX="$3"
: "${CURL_OPTS:=}"

FETCH() {
  # -sS (no -f) so 5xx returns the body instead of erroring under set -e.
  # Fallback to {} so EXTRACT always sees valid JSON.
  curl -sS ${CURL_OPTS} "$URL" 2>/dev/null || echo '{}'
}

EXTRACT() {
  # // empty turns JSON null / missing into nothing (empty stdout).
  jq -r "$JQ_PATH // empty" 2>/dev/null
}

WAKE_WHEN() {
  # Empty cur means the value wasn't there yet — don't wake.
  [[ -n "$cur" && "$cur" =~ $MATCH_REGEX ]]
}

EMIT() {
  echo "VALUE=$cur"
  echo "URL=$URL"
}

POLL_EVERY=30
MAX_WAIT=1800
TAG=JSON_VALUE
