#!/usr/bin/env bash
# Compute Unix epoch from a natural-language time spec.
# Works on both GNU coreutils `date` (Linux, nix-shell on macOS) and macOS BSD
# `date`. Tries GNU first, falls back to BSD with format translation.
#
# Usage:
#   to-epoch.sh "+2 hours"           # relative
#   to-epoch.sh "+45 minutes"
#   to-epoch.sh "+30 seconds"
#   to-epoch.sh "+3 days"
#   to-epoch.sh "+1 week"
#   to-epoch.sh "2026-05-03 09:00"   # absolute (YYYY-MM-DD HH:MM, local TZ)
#
# Prints epoch seconds to stdout. Errors to stderr with exit 2.
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <time-spec>" >&2
  echo "  e.g. '+2 hours', '+45 minutes', '+30 seconds', '+3 days', '+1 week', '2026-05-03 09:00'" >&2
  exit 2
fi

spec=$1

# Pre-validate against the documented spec set, BEFORE dispatching to GNU.
# Without this, GNU `date -d` would silently accept forms ("next friday",
# "tomorrow", "@1234567890") that the BSD fallback cannot parse — breaking
# the cross-platform contract advertised by SKILL.md.
rel_re='^\+[0-9]+[[:space:]]+(hours?|minutes?|min|seconds?|sec|s|days?|weeks?)$'
abs_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}$'
if ! [[ "$spec" =~ $rel_re ]] && ! [[ "$spec" =~ $abs_re ]]; then
  echo "to-epoch.sh: unsupported spec '$spec'" >&2
  echo "  supported: '+N hours|minutes|seconds|days|weeks' or 'YYYY-MM-DD HH:MM'" >&2
  exit 2
fi

# Path 1: GNU date understands all of these natively.
if epoch=$(date -d "$spec" +%s 2>/dev/null); then
  echo "$epoch"
  exit 0
fi

# Path 2: BSD date — translate the GNU-style spec into BSD flags.
# /bin/date is BSD on macOS even when nix puts GNU `date` on PATH.
if [[ "$spec" =~ ^\+([0-9]+)[[:space:]]+hours?$ ]]; then
  /bin/date -v "+${BASH_REMATCH[1]}H" +%s
elif [[ "$spec" =~ ^\+([0-9]+)[[:space:]]+(minutes?|min)$ ]]; then
  /bin/date -v "+${BASH_REMATCH[1]}M" +%s
elif [[ "$spec" =~ ^\+([0-9]+)[[:space:]]+(seconds?|sec|s)$ ]]; then
  /bin/date -v "+${BASH_REMATCH[1]}S" +%s
elif [[ "$spec" =~ ^\+([0-9]+)[[:space:]]+days?$ ]]; then
  /bin/date -v "+${BASH_REMATCH[1]}d" +%s
elif [[ "$spec" =~ ^\+([0-9]+)[[:space:]]+weeks?$ ]]; then
  /bin/date -v "+${BASH_REMATCH[1]}w" +%s
else
  # Absolute spec — pre-validation guarantees the format here. Pin :00 so the
  # epoch is deterministic across runs (BSD `-j -f` otherwise inherits the
  # current second when %S is missing).
  /bin/date -j -f '%Y-%m-%d %H:%M:%S' "${spec}:00" +%s
fi
