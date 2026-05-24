#!/usr/bin/env bash
# Smoke tests for to-epoch.sh — verifies GNU and BSD paths produce the same
# epoch and the error path exits cleanly. Run from repo root or anywhere.
set -euo pipefail

HELPER="$(cd "$(dirname "$0")/.." && pwd)/to-epoch.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# Test 1: relative spec returns a future epoch
got=$("$HELPER" "+2 hours")
now=$(date +%s)
diff=$(( got - now ))
[ "$diff" -gt 7000 ] && [ "$diff" -lt 7400 ] || fail "+2 hours epoch off (diff=${diff}s, expected ~7200)"
pass "relative '+2 hours' produces epoch ~2h in the future"

# Test 2: absolute spec is deterministic (run twice, get same result)
a=$("$HELPER" "2030-01-15 14:30")
sleep 1
b=$("$HELPER" "2030-01-15 14:30")
[ "$a" = "$b" ] || fail "absolute spec not deterministic ($a != $b)"
pass "absolute spec is deterministic across runs"

# Test 3: GNU and BSD paths agree (only meaningful on macOS; on Linux there's
# no /bin/date with -v, so the BSD branch will exit 2 — skip there).
if /bin/date -v +1H +%s >/dev/null 2>&1; then
  gnu=$("$HELPER" "+3 days")
  bsd=$(PATH=/usr/bin:/bin "$HELPER" "+3 days")
  [ "$gnu" = "$bsd" ] || fail "GNU/BSD relative disagree (gnu=$gnu bsd=$bsd)"
  gnu_a=$("$HELPER" "2030-01-15 14:30")
  bsd_a=$(PATH=/usr/bin:/bin "$HELPER" "2030-01-15 14:30")
  [ "$gnu_a" = "$bsd_a" ] || fail "GNU/BSD absolute disagree (gnu=$gnu_a bsd=$bsd_a)"
  pass "GNU and BSD paths agree on relative and absolute specs"
else
  pass "BSD date not available — skipping cross-implementation check (not macOS?)"
fi

# Test 4: bogus spec exits 2 with a usage hint on stderr
if "$HELPER" "junk" 2>/dev/null; then
  fail "bogus spec should have exited non-zero"
fi
out=$("$HELPER" "junk" 2>&1 || true)
echo "$out" | grep -q "supported:" || fail "error output missing 'supported:' hint"
pass "bogus spec exits non-zero with usage hint"

# Test 5: minutes / weeks aliases work
"$HELPER" "+45 minutes" >/dev/null || fail "+45 minutes failed"
"$HELPER" "+1 week" >/dev/null || fail "+1 week failed"
pass "minutes and weeks specs accepted"

# Test 6: singular forms work (regex includes optional trailing 's')
for s in "+1 hour" "+1 minute" "+1 day" "+1 week" "+1 second"; do
  "$HELPER" "$s" >/dev/null || fail "$s failed"
done
pass "singular forms accepted (hour, minute, day, week, second)"

# Test 7: seconds spec + aliases (sec, s)
"$HELPER" "+30 seconds" >/dev/null || fail "+30 seconds failed"
"$HELPER" "+5 sec" >/dev/null || fail "+5 sec failed"
"$HELPER" "+10 s" >/dev/null || fail "+10 s failed"
pass "seconds form accepted (seconds, sec, s)"

# Test 8: pre-validation rejects forms GNU might silently accept on Linux/nix.
# Without pre-validation, "next friday" succeeds via GNU but fails via BSD —
# breaking cross-platform behavior. The pre-check rejects it before dispatch.
for bogus in "next friday" "tomorrow" "@1234567890" "+2 fortnights" "2026/05/03 09:00"; do
  if "$HELPER" "$bogus" 2>/dev/null; then
    fail "spec '$bogus' should be rejected by pre-validation"
  fi
done
pass "pre-validation rejects undocumented specs (cross-platform contract)"

echo "All to-epoch tests passed."
