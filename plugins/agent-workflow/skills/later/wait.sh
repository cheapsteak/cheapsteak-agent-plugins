#!/usr/bin/env bash
# Wait until target Unix epoch, then print payload from text file to stdout.
# Exit triggers a Claude Code <task-notification>, waking the session.
#
# Usage: wait.sh <target_epoch> <text_file> [label]
set -Eeuo pipefail

# Make any early failure visible — Claude Code captures stdout from background
# tasks but stderr alone has been seen to come through empty. Mirror the error
# to stdout via trap so the task output is never opaque. -E propagates ERR
# into functions.
trap 'rc=$?; printf "wait.sh: failed at line %s with exit %s\n" "$LINENO" "$rc"; exit "$rc"' ERR

if [ $# -lt 2 ]; then
  echo "usage: $0 <target_epoch> <text_file> [label]"
  exit 2
fi

target=$1
text_file=$2
label=${3:-wakeup}

# Label is used as a filename and is human-facing in list.sh output.
if ! [[ "$label" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "wait.sh: label must match [A-Za-z0-9._-]: $label"
  exit 2
fi

# Both `-f` and `-r` — the latter catches the case where the path resolves but
# the background-task sandbox can't read it (e.g. nix-shell's per-session tmp
# dir). Without this, the script silently exited 1 with empty output.
if [ ! -f "$text_file" ] || [ ! -r "$text_file" ]; then
  echo "wait.sh: payload not readable from this process: $text_file"
  echo "  (if path is under /var/folders/.../nix-shell.*/ — sandbox can't read it; use ~/.claude/tmp/ instead)"
  exit 2
fi

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

marker_dir="$HOME/.claude/tmp/later"
mkdir -p "$marker_dir"

# Layer 3: self-prune at startup so the directory stays clean even if list.sh
# is never called. Cheap (≤a few file reads on a healthy directory).
shopt -s nullglob
for m in "$marker_dir"/*.lock; do
  prune_marker "$m" || true
done
shopt -u nullglob

marker="$marker_dir/${label}.lock"

# Layer 1: EXIT trap removes our marker on normal exit, error, SIGTERM, SIGINT,
# SIGHUP. SIGKILL bypasses it — Layer 2/3 catch that case. Conditional on
# own_marker so a failed atomic-create doesn't remove a sibling's marker.
own_marker=0
trap '[ "$own_marker" = 1 ] && rm -f "$marker"' EXIT

now_epoch=$(date +%s)
target_human=$(human_time "$target")
started_human=$(human_time "$now_epoch")

# Atomic create via noclobber: if a live sibling survived the self-prune
# above, `>` fails and the subshell exits non-zero. Race-free — two
# concurrent wait.sh calls with the same label produce exactly one winner.
if ! ( set -C; cat > "$marker" <<MARKER
pid=$$
label=$label
target_epoch=$target
target_human=$target_human
started_epoch=$now_epoch
started_human=$started_human
payload_path=$text_file
MARKER
) 2>/dev/null; then
  echo "wait.sh: live wake already exists for label '$label': $marker"
  echo "  (cancel the existing one with TaskStop, or pick a different label)"
  exit 2
fi
own_marker=1

# Poll wall-clock time in <=60s slices so laptop sleep/wake is handled gracefully.
# macOS suspends `sleep` during system sleep, so a long single sleep would resume
# and then run for its full remaining duration. Short slices let the next
# iteration re-check `date +%s` and exit promptly when the target has passed.
while :; do
  now=$(date +%s)
  remaining=$(( target - now ))
  if [ "$remaining" -le 0 ]; then
    break
  fi
  if [ "$remaining" -lt 60 ]; then
    sleep "$remaining"
  else
    sleep 60
  fi
done

printf '=== WAKEUP: %s ===\n' "$label"
cat "$text_file"
rm -f "$text_file"
