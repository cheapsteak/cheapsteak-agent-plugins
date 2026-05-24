# agent-workflow

Process patterns for working with Claude across long sessions.

## Skills

- **adversarial-review** — Stress-test any artifact (design, code, plan) by spawning an Adversary subagent (finds problems blindly) and then a Counterweight subagent (calibrates severity to avoid precision bias). Use when you want a second opinion that's actually challenging, not flattering.
- **later** — Schedule a delayed prompt that fires in the current Claude Code session at a target time, by launching a background bash task that exits at the target. Survives the 1-hour `/loop` ceiling. Examples: "remind me in 4 hours to check the deploy", "tomorrow at 9am run /standup".

## Requirements

- `bash`
- `date` (BSD or GNU)
- The `later/` skill bundles its own helper scripts: `to-epoch.sh`, `wait.sh`, `list.sh`, `lib.sh`, plus a `tests/` directory of shell tests.
