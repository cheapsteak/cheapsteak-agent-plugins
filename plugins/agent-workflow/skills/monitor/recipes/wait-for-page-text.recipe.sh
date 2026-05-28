# Title:   Wait for a text pattern to appear or disappear in a URL response
# Args:    URL PATTERN [MODE]    MODE = appears (default) | disappears
# Example: run-recipe.sh recipes/wait-for-page-text.recipe.sh \
#            https://status.example.com 'All systems operational'
# Env:     REGEX=1     — treat PATTERN as extended regex (default: fixed string)
#          CURL_OPTS   — optional extra flags for curl
#
# `disappears` mode requires PATTERN to have been present at least once before
# it can wake — prevents spurious wake on a page that never matched.

URL="$1"
PATTERN="$2"
MODE="${3:-appears}"
: "${REGEX:=0}"
: "${CURL_OPTS:=}"

FETCH() {
  curl -sS ${CURL_OPTS} "$URL" 2>/dev/null || true
}

EXTRACT() {
  # Output shape: "<HIT_FLAG>|<first matching line>"
  # HIT_FLAG = 1 if PATTERN matched the body, 0 otherwise.
  local body line
  body="$(cat)"
  if [[ "$REGEX" == "1" ]]; then
    line="$(grep -m1 -E -- "$PATTERN" <<< "$body" || true)"
  else
    line="$(grep -m1 -F -- "$PATTERN" <<< "$body" || true)"
  fi
  if [[ -n "$line" ]]; then
    printf '1|%s' "$line"
  else
    printf '0|'
  fi
}

WAKE_WHEN() {
  local cur_hit prev_hit
  cur_hit="${cur%%|*}"
  prev_hit="${prev%%|*}"
  case "$MODE" in
    appears)    [[ "$cur_hit" == "1" ]] ;;
    disappears) [[ "$prev_hit" == "1" && "$cur_hit" == "0" ]] ;;
    *)          return 1 ;;
  esac
}

EMIT() {
  local cur_hit cur_line
  cur_hit="${cur%%|*}"
  cur_line="${cur#*|}"
  echo "MODE=$MODE"
  echo "URL=$URL"
  echo "MATCH=$cur_hit"
  [[ -n "$cur_line" ]] && echo "MATCH_LINE=$cur_line"
}

POLL_EVERY=30
MAX_WAIT=1800
TAG=PAGE_TEXT
