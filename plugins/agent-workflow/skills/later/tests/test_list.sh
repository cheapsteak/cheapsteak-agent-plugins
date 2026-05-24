#!/usr/bin/env bash
# Smoke tests for list.sh. Run from repo root: bash later/tests/test_list.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIST="$REPO_ROOT/later/list.sh"
WAIT="$REPO_ROOT/later/wait.sh"
MARKER_DIR="$HOME/.claude/tmp/later"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# Test 1: list runs without error whether dir is missing, empty, or stale-only
out=$("$LIST" 2>&1) || fail "list.sh exited non-zero on benign state"
pass "list.sh runs cleanly (output: $(echo "$out" | head -1))"

# Test 2: a live wake shows up in the listing
mkdir -p "$MARKER_DIR"
tmp=$(mktemp); echo x > "$tmp"
target=$(( $(date +%s) + 60 ))
"$WAIT" "$target" "$tmp" smoke-list >/dev/null &
bg_pid=$!
sleep 1
out=$("$LIST")
echo "$out" | grep -q "smoke-list" || fail "live wake 'smoke-list' missing from list output: $out"
echo "$out" | grep -q "$bg_pid" || fail "expected pid $bg_pid in list output: $out"
kill "$bg_pid" 2>/dev/null || true
wait "$bg_pid" 2>/dev/null || true
pass "list shows live wake with label and pid"

# Test 3: dead-pid marker is pruned by list (Layer 2 self-heal)
true & dead_pid=$!
wait "$dead_pid" 2>/dev/null || true
cat > "$MARKER_DIR/smoke-dead-list.lock" <<EOF
pid=$dead_pid
label=smoke-dead-list
target_epoch=$(( $(date +%s) + 3600 ))
EOF
"$LIST" >/dev/null
[ ! -f "$MARKER_DIR/smoke-dead-list.lock" ] || fail "list did not prune dead marker"
pass "list prunes dead-pid marker on read"

# Test 4: 30-day reaper removes ancient markers regardless of pid
# Use $$ (this script's pid) so the pid+command checks pass; only the
# target_epoch age should trigger pruning.
ancient=$(( $(date +%s) - 31 * 86400 ))
cat > "$MARKER_DIR/smoke-ancient.lock" <<EOF
pid=$$
label=smoke-ancient
target_epoch=$ancient
EOF
"$LIST" >/dev/null
[ ! -f "$MARKER_DIR/smoke-ancient.lock" ] || fail "30-day reaper did not remove ancient marker"
pass "30-day reaper removes ancient marker"

echo "All list tests passed."
