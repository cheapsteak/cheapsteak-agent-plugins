---
name: drive-pc-apps
description: Drive native Windows desktop GUI apps with cua-driver (cua-computer-use MCP) — read the screen, click, type, navigate menus/forms. Use when automating a Windows application's UI, ESPECIALLY when pixel clicks land in the wrong place on a high-DPI / scaled display, or when a legacy (Delphi/VCL/Win32) app's clicks "do nothing." Covers the DPI click-offset fix and headless foreground control.
---

# Drive PC (Windows) apps

Operate native Windows GUI apps through the `cua-computer-use` MCP (cua-driver). The hard part on Windows is **clicking the right pixel**: on a scaled display (125/150/200%), pixel clicks against a **DPI-unaware legacy app** (most Delphi/VCL/older Win32 apps) land at `1/scale` of the intended spot, so they silently miss. This skill makes interaction reliable.

## Prerequisites

- `cua-computer-use` MCP connected (tools `mcp__cua-computer-use__*` available). If not, see `references/cua-driver-windows-setup.md`.
- For **foreground input on legacy apps** (opening real Win32 menus, driving custom-drawn panes), the driver needs its **UIAccess worker** running. Without it, `bring_to_front` and `dispatch:"foreground"` are rejected by Windows' foreground-lock. One-time setup in `references/uiaccess-foreground-setup.md`.

## The golden rule: never cache geometry

The target window **moves and resizes** between calls (and the screenshot dims change with it). So **re-derive everything every interaction** — never reuse a coordinate, a window rect, or a scale factor from a previous step.

## Core loop (per interaction)

1. **Scale factor** — `get_screen_size()` → read `scale_factor` (e.g. 1.5). It's a monitor property; re-read each time so multi-monitor / DPI changes self-correct.
2. **Window** — `list_windows(pid)` → current `{x, y, width, height}`. Don't assume last turn's bounds.
3. **Snapshot** — `get_window_state(pid, window_id)` → screenshot + UIA tree (with `[element_index N]` tags). This is the source of truth for where things are *now*.
4. **Act** — prefer the coordinate-free path:
   - **Standard control** (toolbar button, menu item, checkbox, scrollbar) → it has an `[element_index]`. Click it with `element_index` — **no DPI compensation needed**, works on backgrounded windows.
   - **Custom-drawn pane** (form grids, embedded-HTML method panes, bespoke navigators) → no UIA element. Use a **pixel click with DPI compensation** (next section), after `bring_to_front`.
5. **Verify** — re-`get_window_state` and confirm the expected change. If nothing changed, the click missed — re-locate and retry; don't fire blind repeats.

## The DPI click-offset fix (the important part)

**Symptom:** pixel clicks land offset (≈⅔ of intended) and "do nothing." **Tell-tale:** the `get_window_state` screenshot shows the app content in only the top-left ~`1/scale` of the image, with **black bands on the right and bottom**. That black margin = a DPI-unaware app captured un-stretched. (Root cause + the upstream driver bug: `references/dpi-click-offset.md`.)

**Fix — multiply screenshot coordinates by the scale factor before clicking:**

```
click_x = screenshot_x * scale_factor
click_y = screenshot_y * scale_factor
```

Example: target at screenshot `(650, 211)`, `scale_factor 1.5` → `click(pid, window_id, x=975, y=316, dispatch="foreground")`. Verified: this navigated a legacy Delphi tax app's form list that uncompensated clicks couldn't touch.

Notes:
- Only DPI-**unaware** apps need this. A DPI-aware app (or one on a 100% display) is 1:1 — compensate only when you see the black-margin tell-tale, or test one click and check whether it landed.
- `count: 2` for double-click; many legacy list/tree rows need it.
- `from_zoom` clicks re-capture through the same buggy path — they inherit the offset, so compensate there too (or just use full-window coords × scale).

### Calibrate the factor (for tiny targets / non-1.5 scales)

`scale_factor` from `get_screen_size` is usually exact. To refine: click 2–3 **UIA elements** by `element_index`, note the screen coords the driver reports, find each element's pixel in the screenshot, and fit `landing = k·input + b` per axis — expect `k ≈ scale_factor`. Re-calibrate per interaction if the window changed monitors.

## Foreground control (legacy menus & custom panes)

Background `PostMessage`/UIA-invoke drives standard controls fine, but **Win32 menus and custom-drawn panes only respond to real foreground input**:

1. `bring_to_front(pid, window_id)` → check `landed_on_target: true`.
2. Then `click`/`press_key` with `dispatch:"foreground"`.

This needs the UIAccess worker (prereq above) — one-time setup: run `scripts/enable-uia-worker.ps1` (elevated), then start the daemon with `CUA_DRIVER_RS_SPAWN_UIA_WORKER=1`. Full details + pitfalls in `references/uiaccess-foreground-setup.md`. Menus are transient — they close when you capture; to read a dropdown, screenshot the **popup window** or use keyboard navigation. If menus won't open and panes won't click, fall back to reading + asking the user to do the one navigation click.

## Reading data out (prefer structure over pixels)

Ranked best→worst for getting values/text out of an app:
1. **UIA tree** (`get_window_state`, `ax` mode) — labeled, exact, no OCR. But custom-drawn content (canvas/grids) won't appear.
2. **App's own export / Print-to-PDF** — for data-heavy forms, have the app print to PDF, then read the PDF. Cleanest and most complete; sidesteps all click/DPI issues.
3. **Screenshot + vision** — works for anything rendered, but it's reading pixels; use when 1–2 aren't available.

## Gotchas

- **Custom-drawn UI is invisible to UIA** — embedded-HTML/CEF panes, owner-drawn grids/navigators show as a bare `Pane` with only a scrollbar. Drive them by compensated pixel clicks, not element index.
- **Single-instance apps** — launching again forwards to the running instance (your new process exits). To instrument from birth, ensure no instance is running first.
- **Window resized mid-task** — always re-snapshot; a stale screenshot's coordinates will be wrong after a resize.
- **`launch_app` may drop file arguments** with spaces/parens — launch via the OS file association or a properly-quoted argv instead.
- **Can read but can't aim?** If screenshots work but clicks miss and you can't get foreground (no UIAccess worker, or a restricted environment), the robust fallback is: you read the screen, the user does the click. Reading is always available; precise aiming on custom panes is the fragile part.
