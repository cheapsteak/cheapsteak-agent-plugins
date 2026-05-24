# git-flow

Commit, push, PR, rebase, and review-feedback workflows on top of `git` + `gh` CLI.

## Skills

- **pr** — commit, push, and open a PR with a compelling title (auto-invokes `monitor-pr`)
- **rebase** — rebase the current branch onto a target with safe conflict resolution, including a special case for generated files
- **monitor-pr** — background-poll a PR for CI failures and reviewer comments, fix and respond in a loop until clean approve + green CI
- **address-pr-feedback** — fetch every comment and review thread on the current PR and build a coherent implementation plan

## Requirements

- `git`
- `gh` CLI (authenticated)
- `python3` (for `address-pr-feedback/scripts/fetch_pr_feedback.py` and the severity-finding parser inside `monitor-pr/poll_pr.sh`)
- `jq`

## Configuration

`monitor-pr` reads `PR_REVIEWER_BOTS` (comma-separated bot logins) to know which reviewer-bot verdicts gate exit. Defaults to `claude[bot]`. Example:

```bash
export PR_REVIEWER_BOTS="claude[bot],my-project-reviewer[bot]"
```
