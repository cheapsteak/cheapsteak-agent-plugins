# Changelog

## [cheapsteak-agent-plugins] 0.9.0

git-flow gains the `stacked-prs` skill.

## [git-flow] 0.4.0

**New:** `stacked-prs` skill — manage a PR stacked on another unmerged branch and re-point it onto `main` after the base merges via a merge queue. Covers the `git rebase --onto <old-base-tip> <branch>` cut, the `gh pr edit --base main` swap, and verifying the resulting branch is clean against `origin/main`.

## [cheapsteak-agent-plugins] 0.8.0

git-flow gains the `subagent-review-loop` skill (fresh-context iterative `/code-review` driver).

## [git-flow] 0.3.0

**New:** `subagent-review-loop` skill — spawn a fresh-context subagent to invoke `/code-review` (arg pass-through, default `high`), triage findings in the driver session (bugfixes/perf addressed directly, user-facing/behavioral changes surfaced first), then loop until no significant findings remain (hard cap 5 rounds). Fresh subagent context avoids same-session bias.

## [computer-use] 0.1.0

New plugin: drive native desktop GUI apps via cua-driver, Windows-focused.

**New:**
- `drive-pc-apps` skill — operate Windows apps through the `cua-computer-use` MCP. Centerpiece is the **DPI click-offset fix**: against DPI-unaware legacy apps (Delphi/VCL/old Win32) on a fractional-scaled display, cua-driver captures un-stretched (`PrintWindow`) but maps clicks to physical screen 1:1, so pixel clicks land at `1/scale` and miss — compensate by `click = screenshot_px × scale_factor`. Also covers headless foreground control via the UIAccess worker, the re-query-geometry-every-interaction rule (windows move/resize), preferring UIA `element_index` over pixels, and reading data out via UIA tree / print-to-PDF.
- Script `scripts/enable-uia-worker.ps1` — one-shot elevated setup that signs the UIAccess worker (auto-discovers the exe), trusts the cert, and flips `EnableSecureUIAPaths`, so headless foreground control works.
- References: `dpi-click-offset.md` (code-verified root cause + upstream-bug references), `uiaccess-foreground-setup.md` (sign the worker, `CUA_DRIVER_RS_SPAWN_UIA_WORKER`, integrity/pipe pitfalls), `cua-driver-windows-setup.md` (install/register on Windows).

## [web-tools] 0.3.0

Reverts the `browse` skill back to Playwright CLI as the default. Adds a brief "Alternative: cua-driver" section pointing at the kept `references/cua-driver-setup.md` for when you need to drive the user's already-open browser.

**Changed:** default browsing path is Playwright CLI again, not cua-driver.
**New:** cua-driver documented as an explicit alternative for already-open-browser / Electron / OAuth-popup cases.

## [git-flow] 0.2.1

**Fixed:** `pr` skill was sometimes asking the user to pick between candidate titles instead of choosing one. Rewrote the title-generation block so the no-choice constraint is the lede, not a footer — the "Generate 3 candidates" framing pattern-matched too easily to "present a list for the user to pick from," and the "do not ask" footer at the end was easy to override. Now the rule comes first, with the reason (the user invoked `/pr` to skip that deliberation).

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
