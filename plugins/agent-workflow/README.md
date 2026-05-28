# agent-workflow

Session patterns for working with Claude across long sessions.

## Skills

- **adversarial-review** — Stress-test any artifact (design, code, plan) by spawning an Adversary subagent (finds problems blindly) and then a Counterweight subagent (calibrates severity to avoid precision bias). Use when you want a second opinion that's actually challenging, not flattering.
- **later** — Schedule a delayed prompt that fires in the current Claude Code session at a target time, by launching a background bash task that exits at the target. Survives the 1-hour `/loop` ceiling. Examples: "remind me in 4 hours to check the deploy", "tomorrow at 9am run /standup".
- **monitor** — Background polling loop that watches an external system (CI, deploys, build jobs, API status, review approvals) and wakes Claude only when state changes. Spends zero tokens while waiting. Bundles ready-to-use polling examples for GitHub PRs and GitLab MRs in `references/`.

## Requirements

- `bash`
- `date` (BSD or GNU)
- `gh` for the GitHub `monitor` reference; `glab` for the GitLab reference
- `jq` (for `monitor`'s reference scripts)
- The `later/` skill bundles its own helper scripts: `to-epoch.sh`, `wait.sh`, `list.sh`, `lib.sh`, plus a `tests/` directory of shell tests.
