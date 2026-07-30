#!/usr/bin/env bash
# poll_pr.sh — block until PR state changes, then report what changed.
# Runs as a background Bash task; Claude reacts to <task-notification>.
#
# Usage: poll_pr.sh <owner/repo> <pr_number> <poll_interval_secs> [max_wait_secs]
#
# Environment:
#   PR_REVIEWER_BOTS — comma-separated bot logins whose verdicts gate exit.
#                      Defaults to "claude[bot]". Entries match exactly unless
#                      they contain `*`, which is a glob. Include the literal
#                      `[bot]` suffix -- `*claude-reviewer` matches nothing.
#                      Example: "claude[bot],*claude-reviewer[bot]"
#
# Self-initializing: gathers its own baseline on startup, then polls for
# changes. No external state file needed — avoids sandbox path issues
# between foreground and background Bash processes.
#
# Loops until a change is detected — does NOT exit on a timer. The
# optional max_wait_secs (default: 3600) is a safety net to prevent
# orphaned processes, not a normal exit path.

set -euo pipefail

REPO="$1"
PR="$2"
POLL_INTERVAL="${3:-60}"
MAX_WAIT="${4:-3600}"

# Build a jq selector expression from the configured bot list.
# Entries match the login exactly unless they contain `*`, which is a glob:
#   claude[bot]             -> only claude[bot]
#   *claude-reviewer[bot]   -> tbd-claude-reviewer[bot], acme-claude-reviewer[bot], ...
# Result looks like: (.user.login | test("^claude\\[bot\\]$")) or (...)
#
# Two escaping traps, both load-bearing:
#  1. jq's test() is a REGEX engine, and a bot login is not a regex. `[bot]` is a
#     character class, so an unescaped `^claude[bot]$` matches "claudeb" and NOT
#     "claude[bot]" -- i.e. the naive form both over- and under-matches. Every
#     metacharacter is escaped first; only `*` is then translated to `.*`.
#  2. The filter is embedded in a jq PROGRAM (gh's --jq takes no --arg), so the
#     escapes must survive jq's string-literal parsing -- hence `\\[`, not `\[`.
#     Entries carrying characters no GitHub login can contain are rejected
#     outright (below) rather than escaped, so they can't inject filter syntax.
BOTS="${PR_REVIEWER_BOTS:-claude[bot]}"
# `printf '%s\n'` (not '%s'): without the trailing newline `read` hits EOF on the
# final entry and the loop body never runs for it -- silently dropping the last
# configured bot, or every bot when only one is configured.
BOT_FILTER=$(printf '%s\n' "$BOTS" | tr ',' '\n' | while IFS= read -r bot; do
  bot="$(printf '%s' "$bot" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -z "$bot" ] && continue
  # GitHub logins are alphanumeric with hyphens; bot logins add a `[bot]` suffix.
  # Anything else is a typo'd env var, and quietly escaping it would build a
  # filter that matches nothing -- indistinguishable from "the bot hasn't
  # reviewed yet", i.e. a silent hour-long wait. Say so and skip the entry.
  case "$bot" in
    *[!A-Za-z0-9._*@/\[\]-]*)
      printf 'monitor-pr: ignoring invalid PR_REVIEWER_BOTS entry: %s\n' "$bot" >&2
      continue ;;
  esac
  pattern="$(printf '%s' "$bot" | sed -e 's/[][\\^$.|?+(){}]/\\\\&/g' -e 's/\*/.*/g')"
  printf '(.user.login | test("^%s$")) or ' "$pattern"
done | sed 's/ or $//')
# An all-whitespace or empty list would yield an empty filter, which is a jq
# syntax error inside select(...) -- fall back to matching nothing explicitly.
[ -z "$BOT_FILTER" ] && BOT_FILTER="false"

# Gather baseline state
prev_review_ids=$(gh api "repos/${REPO}/pulls/${PR}/comments" --jq '[.[].id] | sort | join(",")' 2>/dev/null || echo "")
prev_issue_ids=$(gh api "repos/${REPO}/issues/${PR}/comments" --jq '[.[].id] | sort | join(",")' 2>/dev/null || echo "")
# Use JSON for checks so we can reason about pending vs fail vs pass per check,
# not just regrep on the rendered text (which counts pending as "all passing").
prev_checks=$(gh pr checks "$PR" --repo "$REPO" --json name,state,bucket,link 2>/dev/null \
  | jq -c 'sort_by(.name)' 2>/dev/null || echo "[]")
# jq + empty stdin produces empty stdout with exit 0, so `|| echo "[]"` doesn't fire;
# normalize explicitly so downstream counters never see "" (which bash arithmetic treats as 0).
[[ -z "$prev_checks" ]] && prev_checks="[]"
pr_json=$(gh pr view "$PR" --repo "$REPO" --json reviewDecision,state 2>/dev/null || echo "{}")
prev_decision=$(echo "$pr_json" | jq -r '.reviewDecision // ""')
prev_state=$(echo "$pr_json" | jq -r '.state // "OPEN"')
prev_bot_reviews=$(gh api "repos/${REPO}/pulls/${PR}/reviews" --jq "[.[] | select($BOT_FILTER) | {user: .user.login, state: .state}] | sort_by(.user) | tostring" 2>/dev/null || echo "[]")
# Bot reviewers may also post verdicts as issue comments (sticky comment pattern).
# Track the latest bot comment body to detect verdict changes.
prev_bot_comment=$(gh api "repos/${REPO}/issues/${PR}/comments" --jq "[.[] | select($BOT_FILTER)] | last | .body // \"\"" 2>/dev/null || echo "")

elapsed=0
while (( elapsed < MAX_WAIT )); do
  sleep "$POLL_INTERVAL"
  elapsed=$(( elapsed + POLL_INTERVAL ))

  # Gather current state
  cur_review_ids=$(gh api "repos/${REPO}/pulls/${PR}/comments" --jq '[.[].id] | sort | join(",")' 2>/dev/null || echo "")
  cur_issue_ids=$(gh api "repos/${REPO}/issues/${PR}/comments" --jq '[.[].id] | sort | join(",")' 2>/dev/null || echo "")
  cur_checks=$(gh pr checks "$PR" --repo "$REPO" --json name,state,bucket,link 2>/dev/null \
    | jq -c 'sort_by(.name)' 2>/dev/null || echo "[]")
  [[ -z "$cur_checks" ]] && cur_checks="[]"
  pr_json=$(gh pr view "$PR" --repo "$REPO" --json reviewDecision,state 2>/dev/null || echo "{}")
  cur_decision=$(echo "$pr_json" | jq -r '.reviewDecision // ""')
  cur_state=$(echo "$pr_json" | jq -r '.state // "OPEN"')
  cur_bot_reviews=$(gh api "repos/${REPO}/pulls/${PR}/reviews" --jq "[.[] | select($BOT_FILTER) | {user: .user.login, state: .state}] | sort_by(.user) | tostring" 2>/dev/null || echo "[]")
  cur_bot_comment=$(gh api "repos/${REPO}/issues/${PR}/comments" --jq "[.[] | select($BOT_FILTER)] | last | .body // \"\"" 2>/dev/null || echo "")

  changes=""

  # Compare bot review status (formal PR reviews)
  if [[ "$cur_bot_reviews" != "$prev_bot_reviews" ]]; then
    changes+="BOT_REVIEW_CHANGED\n$cur_bot_reviews\n"
  fi

  # Compare bot review status (issue comment verdicts — sticky comment pattern)
  if [[ "$cur_bot_comment" != "$prev_bot_comment" ]]; then
    # Extract the verdict AND any top-level severity findings in one pass. Doing
    # both in Python (rather than a chain of shell greps) is what lets the verdict
    # be read off the sticky's VERDICT HEADER rather than off "does ✅ appear
    # anywhere in the body" — a body that discusses a ✅ while its header says 🛑
    # otherwise reads as an approve.
    bot_verdict=$(echo "$cur_bot_comment" | python3 -c '
import re, sys
body = sys.stdin.read()

# ── Verdict ────────────────────────────────────────────────────────────────
# Two families of opener, both live:
#   * LLM-authored, from the author personal prompt:  "## ✅ Approve" / "## 🧌 Reject"
#   * Rendered by post_review.build_verdict_banner (opt-in per author, and the
#     default for anyone who sets CC_PR_REVIEW_PREFS_<USER>.verdict_banner):
#       "## ✅ Ready to merge — no findings"
#       "## 🛑 Changes requested — 1 HIGH · 2 MEDIUM"     <- 🛑, NOT 🧌
#       "## ⚠️ Verdict withheld — this round read 0 of 9 changed files"
#       "## 💬 Review posted — no verdict recorded"
# The last two are explicitly NOT approvals ("Treat this as unreviewed"), so they
# must never fall through to a state the caller reads as clean.
_BY_EMOJI = [
    ("\U0001F6D1", "CHANGES_REQUESTED"),      # 🛑 banner
    ("\U0001F9CC", "CHANGES_REQUESTED"),      # 🧌 personal-prompt opener
    ("⚠",     "VERDICT_WITHHELD"),       # ⚠️  nothing was assessed
    ("\U0001F4AC", "NO_VERDICT_RECORDED"),    # 💬 unparseable verdict
    ("✅",     "APPROVED"),               # ✅
]

def classify(text):
    for emoji, verdict in _BY_EMOJI:
        if emoji in text:
            return verdict
    return ""

# Prefer the first markdown heading (the verdict header); fall back to the whole
# body for stickies that open with prose.
verdict = ""
for line in body.splitlines():
    if re.match(r"^#{1,4}\s", line):
        verdict = classify(line)
        if verdict:
            break
if not verdict:
    verdict = classify(body)

# ── Findings (only meaningful on an approve) ───────────────────────────────
# Even on APPROVE the bot can flag findings the body says belong in this PR.
# Top-level severity markers mean "fix here or same-day"; Minors collapsed under
# <details> are explicitly OK to defer.
if verdict == "APPROVED":
    stripped = re.sub(r"<details>.*?</details>", "", body, flags=re.DOTALL)
    # Drop the verdict header itself: "## 🛑 Changes requested — 1 HIGH · 2 MEDIUM"
    # carries severity words that are a tally, not findings.
    stripped = "\n".join(
        l for l in stripped.splitlines() if not re.match(r"^#{1,4}\s+[^A-Za-z0-9]", l)
    )
    # Four rendering shapes seen in the wild, all of which must match:
    #   "### Medium"          heading, title case (legacy matrix reviewer)
    #   "**Medium**"          bold line (missed until 2026-06-10 — a real Medium
    #                         sailed through as a clean APPROVED)
    #   "### MEDIUM — Architect"   heading, UPPERCASE (shadow reviewer; the
    #                         case-sensitive regex missed this one the same way)
    #   "**[HIGH] Core:**"    bracketed inline-finding prefix (shadow reviewer)
    hits = re.findall(
        r"^(?:#{2,4}\s+|\*\*)\[?(CRITICAL|HIGH|MEDIUM)\]?\b",
        stripped,
        flags=re.MULTILINE | re.IGNORECASE,
    )
    seen = []
    for h in hits:
        h = h.capitalize()
        if h not in seen:
            seen.append(h)
    if seen:
        verdict = "APPROVED_WITH_FINDINGS:" + ",".join(seen)

print(verdict)
' 2>/dev/null || echo "")
    prev_bot_comment="$cur_bot_comment"
    # Only wake up Claude when there's a final verdict, not for "working..." placeholder updates
    if [[ -n "$bot_verdict" ]]; then
      changes+="BOT_COMMENT_REVIEW_CHANGED\nVerdict: $bot_verdict\n"
    fi
  fi

  # Compare review comments
  if [[ "$cur_review_ids" != "$prev_review_ids" ]]; then
    new_ids=""
    IFS=',' read -ra CUR_ARR <<< "$cur_review_ids"
    IFS=',' read -ra PREV_ARR <<< "$prev_review_ids"
    for cid in "${CUR_ARR[@]}"; do
      found=0
      for pid in "${PREV_ARR[@]}"; do
        [[ "$cid" == "$pid" ]] && found=1 && break
      done
      [[ $found -eq 0 && -n "$cid" ]] && new_ids="$new_ids $cid"
    done

    if [[ -n "$new_ids" ]]; then
      changes+="NEW_REVIEW_COMMENTS\n"
      for nid in $new_ids; do
        comment_json=$(gh api "repos/${REPO}/pulls/comments/${nid}" --jq '{id, user: .user.login, path, line: .original_line, body}' 2>/dev/null || echo "{}")
        changes+="$comment_json\n"
      done
    fi
  fi

  # Compare issue comments
  if [[ "$cur_issue_ids" != "$prev_issue_ids" ]]; then
    new_ids=""
    IFS=',' read -ra CUR_ARR <<< "$cur_issue_ids"
    IFS=',' read -ra PREV_ARR <<< "$prev_issue_ids"
    for cid in "${CUR_ARR[@]}"; do
      found=0
      for pid in "${PREV_ARR[@]}"; do
        [[ "$cid" == "$pid" ]] && found=1 && break
      done
      [[ $found -eq 0 && -n "$cid" ]] && new_ids="$new_ids $cid"
    done

    if [[ -n "$new_ids" ]]; then
      changes+="NEW_ISSUE_COMMENTS\n"
      for nid in $new_ids; do
        comment_json=$(gh api "repos/${REPO}/issues/comments/${nid}" --jq '{id, user: .user.login, body}' 2>/dev/null || echo "{}")
        changes+="$comment_json\n"
      done
    fi
  fi

  # Compare CI checks
  if [[ "$cur_checks" != "$prev_checks" ]]; then
    # Count buckets from JSON. `bucket` is gh's normalization:
    #   pass | fail | pending | skipping | cancel
    # Unknown/future buckets are treated as non-terminal — we only declare green
    # when every check is explicitly in pass or skip/cancel (see n_total gate below).
    n_total=$(echo "$cur_checks" | jq 'length' 2>/dev/null || echo 0)
    n_fail=$(echo "$cur_checks" | jq '[.[] | select(.bucket == "fail")] | length' 2>/dev/null || echo 0)
    n_pending=$(echo "$cur_checks" | jq '[.[] | select(.bucket == "pending")] | length' 2>/dev/null || echo 0)
    n_pass=$(echo "$cur_checks" | jq '[.[] | select(.bucket == "pass")] | length' 2>/dev/null || echo 0)
    n_skip=$(echo "$cur_checks" | jq '[.[] | select(.bucket == "skipping" or .bucket == "cancel")] | length' 2>/dev/null || echo 0)

    if (( n_fail > 0 )); then
      changes+="CI_FAILURES\n"
      changes+="State: pass=$n_pass pending=$n_pending fail=$n_fail skip/cancel=$n_skip\n"
      failed_names=$(echo "$cur_checks" | jq -r '[.[] | select(.bucket == "fail") | .name] | join(", ")' 2>/dev/null || echo "")
      changes+="Failed checks: $failed_names\n"
      # Get failed run logs
      failed_runs=$(gh run list --branch "$(gh pr view "$PR" --repo "$REPO" --json headRefName --jq '.headRefName')" \
        --repo "$REPO" --status failure --json databaseId,name -L 5 2>/dev/null || echo "[]")
      changes+="Failed runs: $failed_runs\n"
      for run_id in $(echo "$failed_runs" | jq -r '.[].databaseId' 2>/dev/null); do
        log_all=$(gh run view "$run_id" --repo "$REPO" --log-failed 2>/dev/null || echo "(no logs)")
        # A blind tail -100 usually shows whatever ran LAST (e.g. hundreds of
        # passing tests after the one failure). Surface failure-marker lines
        # first — swift-test ✘ / "recorded an issue", GH ::error, generic
        # error/FAIL markers — then a short tail for surrounding context.
        log_hits=$(printf '%s\n' "$log_all" \
          | grep -E '✘|##\[error\]|recorded an issue|error:|FAILED|Fatal error|Expectation failed' \
          | tail -40)
        log_tail=$(printf '%s\n' "$log_all" | tail -25)
        if [ -n "$log_hits" ]; then
          changes+="--- Run $run_id failure lines ---\n$log_hits\n--- Run $run_id log tail ---\n$log_tail\n"
        else
          changes+="--- Run $run_id logs (no failure markers matched; tail) ---\n$log_tail\n"
        fi
      done
    elif (( n_pending == 0 && (n_pass + n_skip) == n_total && n_total > 0 )); then
      prev_checks="$cur_checks"
      # Every check is explicitly pass or skip/cancel (no failures, no pending,
      # no unknown-bucket surprises). Wake up only if bot already approved.
      if echo "$cur_bot_reviews" | grep -q '"state":"APPROVED"' || \
         echo "$cur_bot_comment" | grep -q "✅"; then
        changes+="CI_STATUS_CHANGED\nAll checks passing (pass=$n_pass skip/cancel=$n_skip pending=0 fail=0).\n"
      fi
    else
      # Something changed but checks are still in flight. Don't claim green;
      # update baseline silently and keep polling.
      prev_checks="$cur_checks"
    fi
  fi

  # Compare review decision
  if [[ "$cur_decision" != "$prev_decision" ]]; then
    changes+="REVIEW_DECISION_CHANGED\nWas: $prev_decision, Now: $cur_decision\n"
  fi

  # Check PR state
  if [[ "$cur_state" != "$prev_state" ]]; then
    changes+="PR_STATE_CHANGED\nWas: $prev_state, Now: $cur_state\n"
  fi

  if [[ -n "$changes" ]]; then
    echo -e "$changes"
    exit 0
  fi
done

echo "TIMEOUT after ${MAX_WAIT}s with no changes detected"
