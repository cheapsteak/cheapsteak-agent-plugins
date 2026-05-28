# Changelog

## [cheapsteak-agent-plugins] 0.4.0

`monitor` plugin folded into `agent-workflow`. Six plugins now.

**Removed:** `monitor` (as a standalone plugin).

## [agent-workflow] 0.2.0

**New:** `monitor` skill — background polling that wakes Claude when external state changes. Absorbed from the now-removed `monitor` plugin. Sits alongside `later` (deferred wake-up) and `adversarial-review` (second-opinion review).

## [agent-workflow] 0.1.1

**New:** `/explain` command — injects a prompt to explain using pragmatics and semantics, no syntax.

## [cheapsteak-agent-plugins] 0.3.0

Seven plugins:

- **git-flow** 0.2.0 — `pr`, `rebase`, `monitor-pr`, `address-pr-feedback`
- **skill-authoring-kit** 0.1.0 — `skill-authoring`, `create-plugin`, `claude-hooks`
- **agent-workflow** 0.1.0 — `adversarial-review`, `later`
- **monitor** 0.1.0 — `monitor` (bundles `poll-github-pr.sh` and `poll-gitlab-mr.sh` references)
- **macos-ops** 0.1.0 — `diagnose-memory`
- **web-tools** 0.1.0 — `browse`
- **gql** 0.1.0 — `apollo-optimistic-updates`

`monitor-pr` accepts `$PR_REVIEWER_BOTS` (comma-separated bot logins) to configure which reviewer bots gate exit; defaults to `claude[bot]`.
