# PR Title Examples

Calibration examples covering each category. Use these to tune tone and style — they're not real PRs, but they preserve the patterns: problem-first framing, concrete impact, parenthetical scope, and category discipline.

## Fix
- Fix: Prevent audio page spinner from getting stuck when source filter applied
- Fix: Close pre-commit/CI ruff gap that let import errors slip through
- Fix: Eliminate input lag in search field by capping rendered results at 100
- Fix: Prevent stale status emoji in chat when PR closes before notification posts
- Fix: Unblock Claude PR reviews on PRs that touch workflow files
- Fix: Prevent daily auto-fix agent from failing with expired Claude token
- Fix: Silence 357 Sentry errors from dead third-party integration
- Fix: Stop e2e agent from staging digest artifacts and lock file drift
- Fix: Replace busy pill badges with clean icon+text rows in progress view
- Fix: Prevent subagents from opening PRs on intermediate task commits

## Perf
- Perf: Fix 299 min/call GetUsageByMonth query by removing redundant join
- Perf: Stop scanning 300K index entries to display 37 results
- Perf: Cap facet counts to eliminate 74% singleton labels (27s → fast)
- Perf: Eliminate disk sort spill and serial DataLoader chain on listing page
- Perf: Add partial index for processing velocity query (330ms → sub-ms)
- Perf: Speed up filename search by consolidating 17 ILIKE conditions into single ANY(array)

## Reliability
- Reliability: Add chat alerts for silent parser failures
- Reliability: Run E2E tests against production build to catch chunk splitting bugs
- Reliability: Auto-cleanup stale K8s jobs so parser retries don't 409
- Reliability: Handle transient GitHub API failures in chat PR notification
- Reliability: Prevent Redis OOM by cleaning up orphaned workflow keys hourly
- Reliability: Block load-balancer stickiness in CI after two production incidents
- Reliability: Harden maintenance CronJob against large table scans and OOM
- Reliability: Replace long-lived WebSocket DB connections with per-operation short-lived connections
- Reliability: Add composite indexes for cache staleness checks (Eliminate 30K-91K row scans)

## Ops
- Ops: Prevent Redis OOM cascade (33-min outage) by fixing eviction policy and background services memory
- Ops: Enable instant frontend rollback via commit-addressed index.html archives
- Ops: Add monitor for Redis memory usage (#5178 remediation)
- Ops: Raise RDS Read IOPS alert thresholds to match observed workload baseline
- Ops: Skip visual-regression captures on merge queue builds to eliminate ~5,760 wasted runs/month
- Ops: Replace built-in GitHub chat push notifications with custom GHA workflow
- Ops: Increase prod E2E timeout from 20→30min for K8s node cold starts
- Ops: Split monolithic synthetic test into standalone domain tests for safer iteration

## DX
- DX: Cache Vite production build in E2E CI to avoid redundant 68s rebuilds
- DX: Add `branch_db.sh prune` to clean up orphaned worktree databases
- DX: Fix broken E2E shard balancing — path mismatch made timing data useless
- DX: Let any workflow or local dev trigger multi-source investigation
- DX: Skip synthetic monitoring tests in merge queue
- DX: Speed up chat PR review notifications by dropping CI/E2E gate
- DX: Unlock skills, subagents, and app code editing for the E2E CI agent
- DX: Automate deck data fetching with parallel shell scripts
- DX: Correct cursor rule — constraint is PRs without CI, not direct commits
- DX: Fix format hook corrupting multi-step edits by switching to warn-only mode
- DX: Dispatch Claude investigator on E2E smoke test failures
- DX: Track merge queue entry in chat PR review notifications with :merge-queue:
- DX: Stop squawk false positives on rollback DROP COLUMN
- DX: Add ingest-trigger skill to prevent Claude from hitting workflow engine API directly

## Refactor
- Refactor: Add async sqlc infrastructure for incremental sync-to-async migration
- Refactor: Remove dead db_connection params from async-migrated services
- Refactor: Replace hasty asyncio.to_thread fix with proper SQLAlchemy async engine

## Compound
- Compound: Teach agents the two-phase CTE pattern to prevent disk-spilling JOINs
- Compound: Surface in-progress work and blockers in standup top-level

## Feat
- Feat: Add EXIF metadata to ingest pipeline and detail view
- Feat: Stream tool call activity during agent chat to eliminate dead time
- Feat: Show human-readable tool summaries and thinking activity in agent chat
- Feat: Show agent thinking narration in real time in chat progress view
- Feat: Auto-fix top digest issue by dispatching claude agent to create fix after each daily run
- Feat: Async-resumable chat — Part 2: Don't Feel Broken (when reconnecting to in-progress sessions)
