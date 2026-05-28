# agent-workflow

Session patterns for working with Claude across long sessions.

## Skills

- **adversarial-review** — Stress-test any artifact (design, code, plan) by spawning an Adversary subagent (finds problems blindly) and then a Counterweight subagent (calibrates severity to avoid precision bias). Use when you want a second opinion that's actually challenging, not flattering.
- **later** — Schedule a delayed prompt that fires in the current Claude Code session at a target time, by launching a background bash task that exits at the target. Survives the 1-hour `/loop` ceiling. Examples: "remind me in 4 hours to check the deploy", "tomorrow at 9am run /standup".
- **monitor** — Background polling loop that wakes Claude only when external state changes. Spends zero tokens while waiting. Describe what to watch as a small bash recipe (4 functions: `FETCH`/`EXTRACT`/`WAKE_WHEN`/`EMIT`); the shared `run-recipe.sh` runtime handles the loop, polling, failure tolerance, and output discipline. Ships a 5-recipe library in `recipes/` for common cases (`wait-for-json-value`, `wait-for-page-text`, `wait-for-http-ready`, `wait-for-gh-run`, `wait-for-pr-activity`); recipes can also be passed inline via heredoc for ad-hoc one-offs. Legacy hand-coded polling examples for GitHub PRs and GitLab MRs remain in `references/`.

## Requirements

- `bash`
- `date` (BSD or GNU)
- `gh` for the GitHub `monitor` reference; `glab` for the GitLab reference
- `jq` (for `monitor`'s reference scripts)
- The `later/` skill bundles its own helper scripts: `to-epoch.sh`, `wait.sh`, `list.sh`, `lib.sh`, plus a `tests/` directory of shell tests.
