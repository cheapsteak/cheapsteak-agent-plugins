---
name: later
description: >
  Schedule a delayed prompt that fires in the current Claude Code session at a
  target time, by launching a background bash task that exits at the target.
  Use when the user says "later", "in N hours/days", "wake me", "remind me in",
  "tomorrow", "next week", "schedule a follow-up", or wants to defer work past
  the 1-hour /loop ceiling. The wake payload can be a reminder, an instruction
  to execute, or a slash command.
---

# later

Schedule a delayed prompt to fire in the current Claude Code session. Bypasses the 1-hour `ScheduleWakeup` cap: a background `wait.sh` polls wall-clock time in ≤60s slices and exits at the target epoch — the exit fires `<task-notification>`, which starts a new turn with the payload in task output. The 60s slice cap means the wake fires within ~60s of macOS resuming from sleep, even if the laptop slept past the target.

## When to use vs. alternatives

| Need | Use |
|------|-----|
| One-shot delay, in-session | `later` |
| Recurring, sub-hour, in-session | `/loop` |
| Recurring or one-shot, must survive CC quit | `/schedule` (remote, won't return to this chat) |

## Scheduling — flow

1. **Compute target epoch** using the bundled helper — works on GNU `date` (Linux, nix-shell on macOS) AND BSD `date` (vanilla macOS) without you having to think about which is on PATH:
   ```bash
   target=$(~/.claude/skills/later/to-epoch.sh "+2 hours")        # relative
   target=$(~/.claude/skills/later/to-epoch.sh "2026-05-03 09:00") # absolute (local TZ)
   ```
   Supported relative specs: `"+N hours"`, `"+N minutes"`, `"+N seconds"`, `"+N days"`, `"+N weeks"` (singular forms and `min`/`sec`/`s` aliases also accepted). The helper pre-validates and exits 2 on anything else — even forms GNU `date` would silently accept (`"next friday"`, `"@1234567890"`).

   Human readout for confirmation messages — also dual-syntax:
   ```bash
   date -d "@$target" '+%Y-%m-%d %H:%M %Z' 2>/dev/null \
     || /bin/date -r "$target" '+%Y-%m-%d %H:%M %Z'
   ```

2. **Confirm resolved time to the user** in human form before launching.

3. **Pick a short label** (`flag-cleanup`, `staging-check`). Must match `[A-Za-z0-9._-]+`. Marker creation is atomic (noclobber), so a collision with a live sibling exits 2 race-free; dead-wake markers are auto-pruned and don't block.

4. **Write payload to `~/.claude/tmp/<label>.txt`** (handles multi-line / quoted slash-command args). **Do NOT use `mktemp`** — its default path is often nix-shell-scoped (`/var/folders/.../nix-shell.*/`), which the background-task sandbox can't read. The wake will fail silently.
   ```bash
   mkdir -p ~/.claude/tmp
   payload_file=~/.claude/tmp/<label>.txt
   cat > "$payload_file" <<'EOF'
   <the wake payload>
   EOF
   ```

5. **Launch via the Bash tool with `run_in_background=true`** — one wake per tool call:
   ```bash
   ~/.claude/skills/later/wait.sh <target_epoch> <payload_file> <label>
   ```

   **Scheduling multiple wakes at once: send N parallel Bash tool calls in a single message** (Claude Code dispatches independent tool uses in parallel — same wall time as serializing them, much safer than the alternatives below).

   ⚠️ **Do NOT** parallelize by spawning multiple wakes inside one foreground Bash call (e.g. `bash -lc "wait.sh ..." & bash -lc "wait.sh ..." &`). Both children stay in the tool shell's process group; when the foreground tool finishes, Claude Code's harness cleans up that group with SIGTERM and the wakes die ~seconds after launch. The `EXIT` trap removes their markers, so `list.sh` shows nothing left and the failure is invisible until the wake doesn't fire.

   ⚠️ **Do NOT** detach `wait.sh` (e.g. via `setsid`, `nohup`, or self-relaunch) to "survive" being mis-launched. `<task-notification>` only fires when `wait.sh` exits as the direct child of the harness's background-task wrapper. A detached `wait.sh` orphans itself away from the wrapper — the wrapper sees its direct child exit immediately and emits an empty completion notification, while the real wake later runs with no path back to the session. The skill silently becomes a no-op. Only the `run_in_background=true` path preserves the notification chain.

6. **Verify it armed** before confirming to the user. A wake that failed at startup will have already produced a `<task-notification>` with non-empty output. If the output is still empty after 2 seconds, it's in the wait loop (good):
   ```bash
   sleep 2 && cat <output_file>
   # Empty = waiting. Non-empty = failed early; read the error.
   ```

7. **Confirm to user** in one line:
   > Scheduled wakeup `<label>` for `<human time>`: `<one-line preview>`.

## On wake — flow

`<task-notification>` for a `wait.sh` task. Output file contains:

```
=== WAKEUP: <label> ===
<body>
```

Strip the header, then dispatch on the body:

- **Starts with `/`** → invoke via the `Skill` tool. `/monitor-pr 5495` → `Skill(skill="monitor-pr", args="5495")`.
- **Imperative** ("run X and report", "check Y") → execute as a fresh task.
- **Reminder** ("ask Chang about Z") → surface to user, idle.
- **Ambiguous** → surface to user, ask before acting.

## Cancel / list

**List pending wakes:** `~/.claude/skills/later/list.sh` — pretty-prints each live wake with its label, when it fires (relative + absolute), and PID. Auto-prunes stale markers on every run, so the output is always trustworthy. Works from any shell — independent of Claude Code task state.

**Cancel:** `TaskStop <task_id>` (in-CC) or `kill <pid>` (any shell). Either way, `wait.sh`'s `EXIT` trap removes the marker.

## Marker files

Each live wake writes `~/.claude/tmp/later/<label>.lock` (atomic via noclobber). Fields: pid, label, target_epoch, target_human, started_epoch, started_human, payload_path. `list.sh` reads these; nothing else should rely on the format. Cleanup: `EXIT` trap on the live process, self-prune on every `list.sh` and on each new `wait.sh` startup (handles SIGKILL/crash), and a 30-day reaper. Liveness uses `kill -0` + `ps … grep wait.sh` to defeat PID reuse. Shared liveness/format helpers live in `later/lib.sh`.

## Payload path

Payloads must live somewhere the background-task sandbox can read. `~/.claude/tmp/` works; nix-shell's `mktemp` default does not. `wait.sh` checks readability up front and writes a diagnostic to stdout if the path fails (visible in the task output) — but the cheaper fix is just to not use `mktemp`.

## Constraints

- **CC quit kills pending wakes.** The watcher is a child of the CC process. For survival across restart use `/schedule`.
- **>1 week delays:** prefer `/schedule` — increasingly likely to lose to a CC restart.
