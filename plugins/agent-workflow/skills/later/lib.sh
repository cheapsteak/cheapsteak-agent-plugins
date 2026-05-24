#!/usr/bin/env bash
# Shared helpers for later/* scripts. Source, don't execute.
# shellcheck shell=bash

# human_time <epoch>
# Format an epoch as a human-readable timestamp (cross-platform: GNU first,
# BSD fallback).
human_time() {
  local epoch=$1
  date -d "@$epoch" '+%a %Y-%m-%d %H:%M %Z' 2>/dev/null \
    || date -r "$epoch" '+%a %Y-%m-%d %H:%M %Z'
}

# prune_marker <marker_path>
# Remove the marker if its wake is dead/stale. Returns 0 if pruned (or
# absent), 1 if the wake is live.
#
# Stale predicates:
#   - target was >30 days ago (Layer 4 reaper), OR
#   - PID is dead, OR
#   - PID is alive but running something other than wait.sh (PID reuse).
prune_marker() {
  local m=$1
  [ -e "$m" ] || return 0
  local m_pid m_target_epoch
  m_pid=$(grep -E '^pid=' "$m" 2>/dev/null | head -1 | cut -d= -f2)
  m_target_epoch=$(grep -E '^target_epoch=' "$m" 2>/dev/null | head -1 | cut -d= -f2)

  if [ -n "$m_target_epoch" ] && [ "$m_target_epoch" -lt "$(( $(date +%s) - 2592000 ))" ]; then
    rm -f "$m"; return 0
  fi
  if [ -z "$m_pid" ] || ! kill -0 "$m_pid" 2>/dev/null; then
    rm -f "$m"; return 0
  fi
  if ! ps -p "$m_pid" -o command= 2>/dev/null | grep -q 'wait\.sh'; then
    rm -f "$m"; return 0
  fi
  return 1
}
