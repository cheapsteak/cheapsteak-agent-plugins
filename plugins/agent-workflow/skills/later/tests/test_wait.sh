#!/usr/bin/env bash
# Smoke tests for wait.sh. Run from repo root: bash later/tests/test_wait.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WAIT="$REPO_ROOT/later/wait.sh"
MARKER_DIR="$HOME/.claude/tmp/later"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# Test 1: past target fires immediately and prints payload + label
tmp=$(mktemp)
echo "hello world" > "$tmp"
out=$("$WAIT" 1 "$tmp" smoke-past)
echo "$out" | grep -q '=== WAKEUP: smoke-past ===' || fail "missing header"
echo "$out" | grep -q '^hello world$' || fail "missing body"
[ ! -f "$tmp" ] || fail "temp file should be removed after delivery"
pass "past target fires immediately, prints header+body, removes temp"

# Test 2: target ~3s in the future fires after the delay (bounded)
tmp=$(mktemp)
echo "future" > "$tmp"
target=$(( $(date +%s) + 3 ))
start=$(date +%s)
out=$("$WAIT" "$target" "$tmp" smoke-future)
elapsed=$(( $(date +%s) - start ))
echo "$out" | grep -q '^future$' || fail "missing future body"
[ "$elapsed" -ge 2 ] || fail "fired too early (elapsed=$elapsed)"
[ "$elapsed" -le 65 ] || fail "fired too late (elapsed=$elapsed)"
pass "future target fires within bounded window (elapsed=${elapsed}s)"

# Test 3: default label when not provided
tmp=$(mktemp)
echo "x" > "$tmp"
out=$("$WAIT" 1 "$tmp")
echo "$out" | grep -q '=== WAKEUP: wakeup ===' || fail "default label missing"
pass "default label is 'wakeup' when not provided"

# Test 4: invalid label rejected with exit 2
tmp=$(mktemp); echo x > "$tmp"
if "$WAIT" 1 "$tmp" 'bad label with spaces' >/dev/null 2>&1; then
  fail "invalid label should have been rejected"
fi
rm -f "$tmp"
pass "invalid label rejected (exit 2)"

# Test 5: marker lifecycle (created during wait, removed after delivery)
tmp=$(mktemp); echo lifecycle > "$tmp"
target=$(( $(date +%s) + 3 ))
"$WAIT" "$target" "$tmp" smoke-lifecycle >/dev/null &
bg_pid=$!
sleep 1
[ -f "$MARKER_DIR/smoke-lifecycle.lock" ] || fail "marker not created during wait"
wait "$bg_pid"
[ ! -f "$MARKER_DIR/smoke-lifecycle.lock" ] || fail "marker not removed after delivery"
pass "marker created during wait, removed after delivery"

# Test 6: label collision detected via atomic noclobber
tmp=$(mktemp); echo first > "$tmp"
target=$(( $(date +%s) + 30 ))
"$WAIT" "$target" "$tmp" smoke-collide >/dev/null &
bg_pid=$!
sleep 1
[ -f "$MARKER_DIR/smoke-collide.lock" ] || fail "first wake's marker missing"

tmp2=$(mktemp); echo second > "$tmp2"
out=$("$WAIT" "$target" "$tmp2" smoke-collide 2>&1 || true)
echo "$out" | grep -q "live wake already exists" \
  || fail "expected collision error, got: $out"

# Cleanup: kill the bg wake; its EXIT trap should remove the marker.
kill "$bg_pid" 2>/dev/null || true
wait "$bg_pid" 2>/dev/null || true
rm -f "$tmp2"
[ ! -f "$MARKER_DIR/smoke-collide.lock" ] || fail "marker not cleaned by SIGTERM trap"
pass "label collision detected; SIGTERM trap cleans marker"

# Test 7: dead-pid marker is pruned at startup by new wait.sh
mkdir -p "$MARKER_DIR"
# Pick a PID guaranteed not to be a wait.sh process: spawn `true`, capture its
# pid, wait for it. By the time wait.sh starts, that pid is either dead or
# (if reused) running something that doesn't match `wait\.sh`.
true & dead_pid=$!
wait "$dead_pid" 2>/dev/null || true
cat > "$MARKER_DIR/smoke-dead.lock" <<EOF
pid=$dead_pid
label=smoke-dead
target_epoch=$(( $(date +%s) + 3600 ))
EOF
tmp=$(mktemp); echo x > "$tmp"
"$WAIT" 1 "$tmp" smoke-prune >/dev/null
[ ! -f "$MARKER_DIR/smoke-dead.lock" ] || fail "dead-pid marker not pruned at startup"
pass "dead-pid sibling marker pruned at startup"

echo "All tests passed."
