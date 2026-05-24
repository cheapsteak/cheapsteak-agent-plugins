# monitor

Background polling loop that watches an external system (CI, deploys, build jobs, API status, review approvals, anything) and wakes Claude only when state changes. Spends zero tokens while waiting.

Bundles ready-to-use polling examples for GitHub PRs and GitLab MRs in `references/`.

## Skill

- **monitor** — write a poll script, launch it via `Bash(run_in_background: true)`, idle until `<task-notification>` fires, react to changes, re-chain. The skill explains the pattern and ships two working reference scripts.

## Requirements

- `bash`
- `gh` CLI for the GitHub reference; `glab` for the GitLab reference. Other targets are up to you.
- `jq`
