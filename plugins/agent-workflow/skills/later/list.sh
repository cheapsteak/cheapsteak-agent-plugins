#!/usr/bin/env bash
# List pending `later` wakes. Auto-prunes stale markers on every read so the
# directory is self-healing.
#
# Usage: list.sh
set -Eeuo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

marker_dir="$HOME/.claude/tmp/later"
[ ! -d "$marker_dir" ] && { echo "no pending wakes"; exit 0; }

now=$(date +%s)

format_duration() {
  local s=$1
  if [ "$s" -lt 60 ]; then echo "${s}s"
  elif [ "$s" -lt 3600 ]; then echo "$((s/60))m"
  elif [ "$s" -lt 86400 ]; then echo "$((s/3600))h $(( (s%3600)/60 ))m"
  else echo "$((s/86400))d $(( (s%86400)/3600 ))h"
  fi
}

human_delta() {
  local delta=$1
  if [ "$delta" -lt 0 ]; then
    printf "fired %s ago" "$(format_duration $(( -delta )) )"
  else
    printf "in %s" "$(format_duration "$delta")"
  fi
}

shopt -s nullglob
markers=( "$marker_dir"/*.lock )
shopt -u nullglob

if [ ${#markers[@]} -eq 0 ]; then
  echo "no pending wakes"
  exit 0
fi

# Pass 1: prune dead markers (Layer 2 cleanup — every list call self-heals).
live=()
for m in "${markers[@]}"; do
  if prune_marker "$m"; then
    continue
  fi
  live+=("$m")
done

if [ ${#live[@]} -eq 0 ]; then
  echo "no pending wakes"
  exit 0
fi

# Pass 2: print live markers, sorted by target time.
printf "%-25s %-22s %-22s %s\n" "LABEL" "FIRES" "TARGET" "PID"
for m in "${live[@]}"; do
  target_epoch=$(grep -E '^target_epoch=' "$m" | head -1 | cut -d= -f2)
  echo "$target_epoch|$m"
done | sort -n | while IFS='|' read -r _ m; do
  label=$(grep -E '^label=' "$m" | head -1 | cut -d= -f2-)
  pid=$(grep -E '^pid=' "$m" | head -1 | cut -d= -f2)
  target_epoch=$(grep -E '^target_epoch=' "$m" | head -1 | cut -d= -f2)
  delta=$(( target_epoch - now ))
  printf "%-25s %-22s %-22s %s\n" "$label" "$(human_delta "$delta")" "$(human_time "$target_epoch")" "$pid"
done
