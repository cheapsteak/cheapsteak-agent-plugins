#!/usr/bin/env bash
# run-recipe.sh — recipe runtime for the monitor skill.
#
# Usage: run-recipe.sh <recipe-path|-> [recipe-args...]
#
# `-` reads the recipe body from stdin (typical heredoc invocation).
# A path sources that file directly. Remaining args are passed to the recipe
# as $1, $2, ... and should be captured at the top of the recipe body.
#
# A recipe is a bash blob defining four functions and three env vars:
#   FETCH()     - raw response on stdout
#   EXTRACT()   - stdin -> one value to diff/match on stdout
#   WAKE_WHEN() - predicate over $cur and $prev; exit 0 to wake, 1 to keep polling
#   EMIT()      - structured output when waking (line-oriented TAG_SUBKEY=value)
#   POLL_EVERY  - seconds between polls
#   MAX_WAIT    - upper bound; loop exits with TIMEOUT when exceeded
#   TAG         - short prefix printed as the first line of the wake payload
#
# Stdout discipline: exactly one of TAG+EMIT-output, TIMEOUT, or FETCH_FAILED.
# Stderr: all debug noise. Exit code: 0 on normal exit; non-zero only on
# setup errors (missing functions, missing env vars, missing recipe file).

set -uo pipefail
# Deliberately NOT set -e: WAKE_WHEN returning 1 is "keep polling," not error.

_mon_log() { echo "[monitor] $*" >&2; }
_mon_die() { echo "[monitor] ERROR: $*" >&2; exit 2; }

_mon_recipe_tmp=""
_mon_cleanup() { [[ -n "$_mon_recipe_tmp" ]] && rm -f "$_mon_recipe_tmp"; }
trap '_mon_cleanup' EXIT
# Interruptible-sleep + trap so SIGTERM exits within ~1s.
trap 'exit 130' INT TERM

[[ $# -ge 1 ]] || _mon_die "usage: $0 <recipe-path|-> [recipe-args...]"
_mon_arg="$1"; shift

# Source lib.sh (multi-signal helpers: diff_changed, diff_new_ids, diff_bucket_fail)
_mon_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [[ -f "$_mon_dir/lib.sh" ]]; then
  # shellcheck disable=SC1091
  source "$_mon_dir/lib.sh"
fi

# Source the recipe
if [[ "$_mon_arg" == "-" ]]; then
  # Read stdin into a tempfile, then source. Avoids `source /dev/stdin`,
  # whose behavior under run_in_background harnesses is fragile.
  _mon_recipe_tmp="$(mktemp -t monitor-recipe.XXXXXX)"
  cat > "$_mon_recipe_tmp"
  # shellcheck disable=SC1090
  source "$_mon_recipe_tmp"
elif [[ -f "$_mon_arg" ]]; then
  # shellcheck disable=SC1090
  source "$_mon_arg"
else
  _mon_die "recipe not found: $_mon_arg"
fi

# Validate the four required functions
for _mon_fn in FETCH EXTRACT WAKE_WHEN EMIT; do
  declare -F "$_mon_fn" >/dev/null || _mon_die "recipe missing required function: $_mon_fn"
done

# Validate the three required env vars (must be set AND non-empty)
: "${POLL_EVERY:?[monitor] recipe missing POLL_EVERY env var}"
: "${MAX_WAIT:?[monitor] recipe missing MAX_WAIT env var}"
: "${TAG:?[monitor] recipe missing TAG env var}"

# Capture pipeline FETCH | EXTRACT, with trailing-whitespace normalization.
# Returns 0 on success with the extracted value on stdout, non-zero on failure
# with the failure logged to stderr via _mon_log.
_mon_capture() {
  local _out _err _status
  _err="$(mktemp -t monitor-err.XXXXXX)"
  if _out="$( FETCH 2>>"$_err" | EXTRACT 2>>"$_err" | sed -e 's/[[:space:]]*$//' )"; then
    rm -f "$_err"
    printf '%s' "$_out"
    return 0
  fi
  _status=$?
  if [[ -s "$_err" ]]; then
    _mon_log "FETCH|EXTRACT failed (exit $_status): $(tr '\n' ' ' < "$_err")"
  else
    _mon_log "FETCH|EXTRACT failed (exit $_status)"
  fi
  rm -f "$_err"
  return 1
}

# Capture baseline. A baseline failure is fatal — we have nothing to diff against.
_mon_log "baseline capturing (TAG=$TAG POLL_EVERY=${POLL_EVERY}s MAX_WAIT=${MAX_WAIT}s)"
prev=""
if ! prev="$( _mon_capture )"; then
  _mon_die "baseline FETCH|EXTRACT failed; cannot start"
fi
_mon_log "baseline captured"

# Poll loop
_mon_elapsed=0
_mon_fail_count=0
_mon_max_fails=5

while (( _mon_elapsed < MAX_WAIT )); do
  sleep "$POLL_EVERY" & wait $!
  _mon_elapsed=$(( _mon_elapsed + POLL_EVERY ))

  cur=""
  if ! cur="$( _mon_capture )"; then
    _mon_fail_count=$(( _mon_fail_count + 1 ))
    if (( _mon_fail_count >= _mon_max_fails )); then
      echo "FETCH_FAILED"
      exit 0
    fi
    continue
  fi
  _mon_fail_count=0

  if WAKE_WHEN; then
    printf '%s\n' "$TAG"
    EMIT
    exit 0
  fi
  prev="$cur"
done

echo "TIMEOUT after ${MAX_WAIT}s"
exit 0
