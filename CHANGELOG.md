# Changelog

## [agent-workflow] 0.3.0

`monitor` skill: recipe DSL runtime + 5-recipe library.

**New:**
- `run-recipe.sh` runtime — sources a 4-function bash recipe (`FETCH`/`EXTRACT`/`WAKE_WHEN`/`EMIT`) plus 3 env vars (`POLL_EVERY`/`MAX_WAIT`/`TAG`) and owns the poll loop, baseline capture, failure tolerance, signal handling, and stdout/stderr discipline. Recipes can be passed as a file path or inline via stdin heredoc.
- `lib.sh` helpers (`diff_changed`, `diff_new_ids`, `diff_bucket_fail`) for multi-signal recipes that batch many signals into one fetch.
- 5 shipped recipes in `recipes/`: `wait-for-json-value`, `wait-for-page-text`, `wait-for-http-ready`, `wait-for-gh-run`, `wait-for-pr-activity`. All portable (no project- or org-specific names) and named `wait-for-*` for greppability.

**Changed:** `monitor/SKILL.md` rewritten around the recipe DSL — leads with the heredoc form, documents the four-function contract + three env vars, contract rules (WAKE_WHEN exit-code semantics, line-oriented `TAG_SUBKEY=value` EMIT shape, stdout vs stderr discipline, runtime hardenings), recipe library index, and the multi-signal pattern. Legacy `references/` scripts kept as the de-emphasized fallback for cases the DSL doesn't fit.

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
