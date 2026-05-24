---
name: address-pr-feedback
description: Fetch and analyze all feedback on the current PR to create a comprehensive implementation plan. Use when the user says "address pr feedback", "handle pr comments", "review pr feedback", "address review comments", or wants to systematically work through PR review threads.
---

# Address PR Feedback

Fetch and analyze all feedback on the current PR to create a comprehensive implementation plan.

## Step 1: Gather Information

Use the bundled script to fetch all PR feedback as structured JSON:

```bash
# Auto-detect PR from current branch
python scripts/fetch_pr_feedback.py

# Or specify a PR number
python scripts/fetch_pr_feedback.py --pr-number 123

# Include resolved threads (default: only unresolved)
python scripts/fetch_pr_feedback.py --include-resolved
```

The script is at `scripts/fetch_pr_feedback.py` relative to the skill directory. It wraps multiple `gh` API calls (PR metadata, issue comments, review threads via GraphQL, recent commits) into a single JSON output containing: `pr` (number, title, url), `reviews`, `issue_comments`, `review_threads` (with thread IDs for later resolution), and `recent_commits`.

## Step 1a: Wait for Claude Review (if in progress)

If the project runs an automated Claude PR review via GitHub Actions (e.g. a `claude-pr-review.yml` workflow that posts a sticky summary comment from `github-actions[bot]`), check whether that review has completed for the current commit before continuing.

**If NO Claude review summary comment exists:**

```bash
# Find the review workflow (filename is project-specific)
gh workflow list --json name,path | jq '.[] | select(.name | test("claude.*review"; "i"))'

# Check if it's currently running for the current commit
gh run list --workflow=<workflow-filename>.yml --json status,headSha,conclusion --limit 3

# Compare against current PR head SHA
gh pr view --json headCommit -q .headCommit.oid
```

If the workflow is `in_progress` or `queued` for the current commit:
1. Inform the user that the automated review is still running
2. Wait 30 seconds and check again
3. Repeat until workflow completes, then re-fetch all comments

**Skip waiting if:** The review summary comment already exists, the workflow has already completed/failed for this commit, or the project doesn't run an automated Claude review.

## Step 2: Deep Analysis

**Read ALL feedback carefully:**
- Review every comment and review thread
- Cross-reference against recent commits to identify already-addressed items
- Note the timestamp of comments vs commits
- **Distinguish AI feedback from human feedback** — AI inline comments from bot accounts should default to being addressed; human feedback requires more careful consideration

**For each piece of feedback, default posture is: address and resolve.** Read the comment, implement the fix, reply, and resolve the thread. Only skip an inline comment if it:
- Contradicts an established codebase pattern (cite the file)
- Would break functionality
- Is factually wrong about what the code does

Even when skipping, always reply to the thread explaining why before resolving.

**Categorize feedback into:**
1. **Critical** — Blocking merge, must be fixed (security vulnerabilities, breaking changes, test failures, architecture violations)
2. **Important** — Should address before merge (performance concerns, code quality, missing error handling, unclear naming)
3. **Minor** — Nice to have (style preferences, comment wording, optional refactoring)
4. **Dismiss/Push back** — Invalid suggestions, bikeshedding, or misunderstandings
5. **Already addressed** — Fixed in recent commits

**Think deeply about:**
- Root causes — do multiple comments point to the same underlying issue?
- The best way to address related feedback together
- Potential side effects or edge cases — especially race conditions from new async work competing with existing data fetches
- Whether suggested changes align with the PR's original intent
- If E2E tests are failing persistently (2+ runs), investigate whether the PR introduced a race condition before dismissing as flaky

**Common AI review false positives:**
- Excessive defensive coding suggestions
- Over-engineering for unlikely edge cases
- Style preferences disguised as correctness issues
- Suggestions that don't account for existing codebase patterns
- Over-mocking recommendations in tests

## Step 3: Create Implementation Plan

**Propose a coherent plan that:**
- Groups related changes together logically
- Orders work from foundational to superficial
- Explains WHY each change should be made
- **Explicitly lists feedback you recommend dismissing** (with reasoning)
- Lists specific files/functions that need modification

**Present the plan with:**
- Summary of total feedback items and their categories (including dismissals)
- Recommended implementation order
- Estimated scope/complexity of each change
- Any questions or concerns about specific feedback

**When to ask the user vs. implement directly:**
- **Implement directly** when the correct fix is clear — the feedback points to a real bug, a missing edge case, or a straightforward improvement where there's one obviously right answer
- **Ask the user** only when the feedback involves a genuine judgment call — trade-offs between competing approaches, feedback that conflicts with the PR's intent, or suggestions where reasonable engineers would disagree
- Don't ask for approval on the overall plan if every item has a clear path. Just present what you're about to do and start implementing. If even one item needs a judgment call, present that item and implement the rest in parallel.

## Step 4: Implementation

1. **Implement changes systematically**
   - Work through the plan in the proposed order
   - **One commit per logical change** — separate commits for each fix so reviewers can see what addressed what
   - **Batch the push** — do NOT push until all changes are committed. A single `git push` at the end avoids triggering recursive AI reviews (each push can trigger a new review cycle)
   - Run tests/CI as appropriate

2. **For inline comment suggestions with one-click fixes:**
   - If the reviewer provided a concrete code suggestion, apply it directly
   - Verify the suggestion is correct before applying — don't blindly accept

3. **Verify completion**
   - Ensure all critical and important feedback addressed
   - Test changes thoroughly
   - Review the diff to confirm quality

4. **Reply and resolve inline review threads**
   - For each addressed thread, reply explaining what was done, then resolve
   - **Never resolve a thread without replying first**

```bash
# Reply to the thread explaining what was done
gh api graphql -f query='mutation { addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: "THREAD_ID", body: "Done — [brief explanation of what was changed]"}) { comment { id } } }'

# Resolve the thread
gh api graphql -F threadId="THREAD_ID" -f query='mutation($threadId: ID!) { resolveReviewThread(input: {threadId: $threadId}) { thread { id } } }'
```

## Guidelines

**Never:**
- Skip reading any comment or review
- Make assumptions about ambiguous feedback without asking
- Resolve comment threads before actually addressing the feedback
- Resolve inline review threads without replying first
- Push before all commits are ready

**Always:**
- Read every piece of feedback thoroughly
- Cross-reference with recent commits
- Think critically about whether changes make sense
- Verify changes work before resolving threads
- Reply to each inline review thread before resolving it
- Default to addressing inline comments rather than dismissing them
- Distinguish between AI and human feedback (weight human feedback more heavily)
- One commit per fix, one push at the end
- Implement clear fixes directly; only ask for genuine judgment calls
