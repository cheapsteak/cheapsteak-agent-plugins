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

**Top processes by real memory (RSS):**
```bash
ps -eo rss,pid,command | sort -k1 -rn | head -30
```

RSS (Resident Set Size) = actual physical RAM used. Ignore virtual memory (VSZ) — Electron apps reserve 1800+ GB virtual but use only 40-160 MB physical.

**Sum memory by application name:**
```bash
ps -eo rss,command | awk '{split($2,a,"/"); name=a[length(a)]; mem[name]+=$1} END {for(n in mem) printf "%8.1f MB  %s\n", mem[n]/1024, n}' | sort -rn | head -20
```

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

## Step 5: Take action

After identifying the culprits, common fixes:

- Close unused editor workspaces/windows (biggest wins with Cursor/VS Code)
- Kill duplicate Claude sessions: `ps aux | grep -i "[c]laude" | grep -v grep`
- Disable heavy extensions (Continue/ONNX, Copilot) in workspaces that don't need them
- Restart the worst offender app to clear accumulated memory

**Monitor improvement after cleanup:**
```bash
sysctl vm.swapusage
```

## Notes

- Activity Monitor's memory column is often misleading for Electron apps — always verify with `ps -eo rss`
- Electron/Chromium apps reserve massive virtual memory (1800+ GB per helper) but use minimal physical RAM
- Death by a thousand cuts is the typical pattern: many moderate processes (8 Claude sessions + 20 Cursor workspaces + Chrome tabs) exhaust RAM collectively
- macOS encrypted swap adds CPU overhead on top of I/O cost when thrashing
