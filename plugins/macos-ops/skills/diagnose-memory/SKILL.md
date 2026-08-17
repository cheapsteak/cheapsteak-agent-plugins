---
name: diagnose-memory
description: Diagnose macOS memory usage and identify what's consuming RAM. Use when the system is slow, swap is high, or Activity Monitor shows suspicious numbers.
---

# Diagnose Memory

Systematic diagnosis of macOS memory pressure using terminal commands. Activity Monitor is often misleading (shows virtual memory, not actual RAM) — these commands show the truth.

## Step 1: System-level memory overview

**Check free memory and paging activity:**
```bash
vm_stat
```

Key lines to interpret:
- `Pages free` × 16384 = free bytes (divide by 1073741824 for GB)
- `Pages active` = memory in active use
- `Pageouts` > 0 means system is swapping to disk
- High `Pages purged` indicates aggressive memory reclamation

**Check swap usage:**
```bash
sysctl vm.swapusage
```

Swap above 80% indicates severe memory pressure. Above 95% means the system is thrashing.

## Step 2: Find actual memory consumers

### Rank by compressed + resident, NOT by RSS alone

**This is the single most important step, and RSS alone will mislead you.** When a
process goes dormant, macOS compresses its pages: RSS shrinks while the process
still *owns* the memory. So an RSS-sorted list systematically hides the dormant
processes — which are usually the best reclaim targets — and over-weights whatever
happens to be active right now.

```bash
top -l 2 -n 30 -o cmprs -stats pid,mem,cmprs,command 2>/dev/null | awk '/^PID/{n++} n==2'
```

`cmprs` is the per-process compressed footprint. Real footprint ≈ `mem + cmprs`.
Use `-l 2` and take the second sample — the first is a garbage warm-up snapshot.

**Aggregate real footprint by class:**
```bash
top -l 2 -n 400 -o cmprs -stats pid,mem,cmprs,command 2>/dev/null | awk '/^PID/{n++} n==2' | tail -n +2 | awk '
function conv(x,  u,n){gsub(/[+-]$/,"",x); u=substr(x,length(x),1); n=substr(x,1,length(x)-1)+0; if(u=="G")return n*1024; if(u=="M")return n; if(u=="K")return n/1024; return 0}
{cmd=$4; for(i=5;i<=NF;i++) cmd=cmd" "$i
 k="(other)"
 if (cmd ~ /SourceKitService/) k="SourceKitService"
 else if (cmd ~ /pyright/) k="pyright"
 else if (cmd ~ /^node/) k="node"
 else if (cmd ~ /claude/) k="claude sessions"
 else if (cmd ~ /Chrome/) k="Chrome"
 tot[k]+=conv($2)+conv($3); cnt[k]++}
END {for (i in tot) printf "%8.1f GB  %4d procs  %s\n", tot[i]/1024, cnt[i], i}' | sort -rn
```

**Expect the class totals to sum well past physical RAM.** That is not a bug in the
math — it is *logical* demand measured against physical capacity, and the ratio is
the oversubscription factor. Summing to ~120 GB on a 48 GB machine means ~2.5×
oversubscribed, which is precisely why the compressor is full and `kernel_task` is
pegged.

### RSS as a secondary view

```bash
ps -eo rss,pid,command | sort -k1 -rn | head -30
```

RSS = pages currently resident. Still useful for *active* processes, but never
conclude "X is the problem" from RSS alone. Ignore virtual memory (VSZ) — Electron
apps reserve 1800+ GB virtual but use only 40-160 MB physical.

**Sum RSS by application name:**
```bash
ps -eo rss,command | awk '{split($2,a,"/"); name=a[length(a)]; mem[name]+=$1} END {for(n in mem) printf "%8.1f MB  %s\n", mem[n]/1024, n}' | sort -rn | head -20
```

Beware the catch-all bucket. If your classifier dumps 20 GB into `(other)`, that
bucket is your answer — break it down before drawing conclusions from the named ones.

## Step 2b: Separate memory pressure from CPU saturation

A huge load average with modest CPU usage means threads are **blocked**, not busy.
Check the process state histogram before blaming any one app:

```bash
ps -axo state | tail -n +2 | cut -c1 | sort | uniq -c | sort -rn
```

- `R` — runnable. Compare against core count (`sysctl -n hw.ncpu`); far more `R`
  than cores is genuine CPU oversubscription.
- `U` / `D` — uninterruptible sleep, usually blocked on I/O. Under heavy swap this
  is a *symptom* of memory pressure, not an independent problem.
- `Z` — zombies. A large count means something forks without reaping.

**Find who is leaking zombies:**
```bash
ps -axo ppid,state | awk '$2 ~ /^Z/ {print $1}' | sort | uniq -c | sort -rn | head
```

Then confirm whether it is still growing (a static count is a past burst, not an
active leak) by sampling twice ~25s apart. Zombies are cheap; a *growing* count is
the signal, not the absolute number.

**`kernel_task` and `WindowServer` at the top are downstream symptoms.** `kernel_task`
burning CPU means it is doing memory compression. `WindowServer` saturating makes the
whole UI feel laggy — including terminal keystroke echo — even when the underlying
subsystem is instant. Always measure the subsystem the user is complaining about
before assuming it is at fault (e.g. time a tmux round-trip: if it returns in 0.02s,
tmux is not your problem, the compositor is).

## Step 3: Deep dive into specific applications

**Count processes for a specific app (e.g., Cursor, Code, claude):**
```bash
ps aux | grep -ci "[C]ursor"
```

The `[C]` bracket trick excludes the grep process itself from results.

**Sum RSS for a specific app:**
```bash
ps -eo rss,command | grep -i "[C]ursor" | awk '{sum+=$1} END {printf "%.2f GB\n", sum/1048576}'
```

**Inspect what an extension host or helper process has loaded:**
```bash
lsof -p <PID> | grep '\.dylib\|\.node\|\.so' | head -20
```

Useful for finding heavy native libraries (e.g., ONNX Runtime at 21 MB per process).

## Step 4: Identify multiplied processes

Electron apps (VS Code, Cursor, Chrome) spawn per-window/workspace processes. Key multipliers:

- **Extension hosts**: one per workspace, each loads all extensions
- **Renderer processes**: one per tab/window
- **Helper processes**: language servers, file watchers, terminal hosts

**List extension host processes with memory:**
```bash
ps -eo rss,command | grep -i "extensionHost\|extension-host" | awk '{printf "%6.0f MB  %s\n", $1/1024, $0}'
```

### Language servers multiply per project, and nobody counts them

The worst offenders in a multi-worktree setup are language servers, because you get
one (or more) per open project and they are invisible in any per-app view:

```bash
for p in pyright-langserver SourceKitService tsserver gopls rust-analyzer clangd; do
  printf "%-22s %s\n" "$p" "$(pgrep -f "$p" 2>/dev/null | wc -l | tr -d ' ')"
done
```

Counts in the dozens are normal-looking and enormous in aggregate — one real case
had **66 `pyright-langserver` and 12 `SourceKitService`** instances, the latter at
roughly 1.2 GB *logical* each. Several had been idle for 5+ days.

## Step 4b: Find orphaned and wedged processes

Processes reparented to launchd (`ppid=1`) have lost whoever started them. Nothing
will ever clean them up.

```bash
ps -axo pid,ppid,rss,etime,state,command | awk '$2==1 && $4 ~ /-/' | head -20
```

**Cross-check elapsed time against consumed CPU time** — that ratio is what separates
a wedged process from a working one:

```bash
ps -o pid,etime,time,%cpu,stat -p <PID>
```

Days of `ELAPSED` against seconds of `TIME` means parked, not working. Also check
whether a server process is actually serving:

```bash
lsof -p <PID> | grep -E 'cwd|LISTEN'
```

A dev server holding no `LISTEN` socket never finished starting, or has been wedged
since it did.

### The long-lived-dev-server leak

A recurring pattern worth checking for explicitly: an agent or script starts a
long-running dev server (Storybook, Vite, a watcher) in the foreground; its session
or terminal later dies; the server is reparented to launchd and survives
indefinitely. A real instance ran **10 days** consuming 4.7 seconds of CPU total,
holding memory the whole time, in a worktree that had since been *archived*.

The generalizable lesson: **tearing down a workspace kills its terminal, not the
process tree that escaped it.** Any tool that manages workspaces or sessions should
kill the process *group*, not just the shell. When auditing, check whether long-lived
child processes outlive the workspace that owns them:

```bash
lsof -p <PID> 2>/dev/null | awk '/cwd/{print $NF}'   # then check if that path is still an active workspace
```

## Step 5: Take action

### Reclaim in cost order — free wins first

Work outward from what costs the user nothing:

1. **Respawnable tooling daemons** — language servers (`pyright-langserver`,
   `SourceKitService`, `tsserver`, `gopls`), file watchers, npx-spawned MCP helpers.
   These restart on demand; the cost is a few seconds of re-index. No judgment call
   required, so always sweep these before proposing anything disruptive.
2. **Orphans and wedged processes** (`ppid=1`, days elapsed / seconds of CPU).
   Nothing legitimate holds a package install or dev server open for a week.
3. **Idle heavyweight apps** — a second browser, chat apps with runaway renderers.
4. **The user's actual work** — only after the above, and only with their explicit
   say-so on what to pause.

**Before proposing that the user shut down their own work, verify there is no free
waste first.** Check whether sessions belong to live or archived/closed workspaces —
if they are all live, say so plainly rather than implying an easy win exists.

```bash
# example sweep of respawnable daemons
pkill -f pyright-langserver; pkill -f SourceKitService
```

**Monitor improvement after cleanup — track used *and* total swap:**
```bash
sysctl vm.swapusage
vm_stat | awk '/page size/{ps=$8} /Pages free/{f=$3} /Pages occupied by compressor/{c=$5} END {gsub(/\./,"",f);gsub(/\./,"",c); printf "free=%.2fG compressed=%.1fG\n", f*ps/1073741824, c*ps/1073741824}'
```

macOS **grows and shrinks the swap file dynamically**, so the total moves between
measurements. Reporting only "used" makes a real improvement look like a regression
(or vice versa) — quote both, and expect total swap to shrink after a good sweep.

## Notes

- **RSS hides dormant processes.** Compression shrinks RSS while the process still
  owns the memory, so an RSS-sorted list points at the wrong culprit. Rank by
  `mem + cmprs`. This is the single easiest mistake to make in this diagnosis.
- Activity Monitor's memory column is often misleading for Electron apps — always verify with `ps -eo rss`
- Electron/Chromium apps reserve massive virtual memory (1800+ GB per helper) but use minimal physical RAM
- Death by a thousand cuts is the typical pattern: many moderate processes (dozens of
  agent sessions + language servers + editor workspaces + browser tabs) exhaust RAM
  collectively. There is frequently **no single runaway process** — if the largest
  single consumer is a few hundred MB, stop hunting for one and start counting classes.
- macOS encrypted swap adds CPU overhead on top of I/O cost when thrashing
- **A subsystem that measures fast is not the bottleneck.** Under memory pressure the
  compositor makes everything feel slow. Time the specific subsystem before blaming it.
- Conditions change fast on a loaded machine — load averages swung 199 → 9 within
  half an hour in one session as background work drained. **Re-measure before acting
  on numbers more than a few minutes old**, and re-measure after acting rather than
  assuming the fix landed.
