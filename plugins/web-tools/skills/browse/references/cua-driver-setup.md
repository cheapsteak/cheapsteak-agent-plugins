# cua-driver setup

[cua-driver](https://github.com/trycua/cua/tree/main/libs/cua-driver) is a background
computer-use tool for macOS (Windows/Linux too). It drives apps via the macOS
accessibility API + screen capture and exposes an MCP server, so Claude Code can read
and operate any window — including your real, already-logged-in browser — without
stealing focus or moving your cursor.

If the `cua-computer-use` MCP tools (`mcp__cua-computer-use__*`) are already available in
your session, it's installed — skip to the bottom. Otherwise:

## Install (macOS, ~1 min, no sudo)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/scripts/install.sh)"
```

Installs `CuaDriver.app` to `/Applications`, a `cua-driver` CLI to `~/.local/bin`, and
links a `cua-driver` skill pack into agent config dirs. (Windows: run
`irm https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/scripts/install.ps1 | iex`.)

## Register the MCP server with Claude Code

```bash
claude mcp add-json -s user cua-computer-use \
  '{"command":"/Users/'"$USER"'/.local/bin/cua-driver","args":["mcp","--claude-code-computer-use-compat"]}'
```

`-s user` makes it available in every project. `--claude-code-computer-use-compat` makes
the `screenshot` tool window-scoped so Claude's vision grounds on a specific window. Verify
with `claude mcp get cua-computer-use` (should say `Connected`). New tools appear after a
fresh Claude Code session.

## Grant macOS permissions (one time)

```bash
cua-driver permissions grant     # launches CuaDriver so the grant sticks to the driver
cua-driver permissions status    # both should read ✅
```

Toggle **Accessibility** and **Screen Recording** on for CuaDriver in the System Settings
panes it opens. Until both are granted, the click/type/screenshot tools are blocked.

## Enable JavaScript / DOM reads (optional, for browsers)

Reading the DOM or running JS in Chrome/Brave/Edge needs "Allow JavaScript from Apple
Events". Either flip it manually (Chrome menu → **View → Developer → Allow JavaScript from
Apple Events**) or have Claude run `page(action: enable_javascript_apple_events)` — note the
tool path **quits and relaunches the browser**, and once on, any process that can send Apple
Events to the browser can run JS in your pages.

## Deeper reference

The installer links a full skill at `~/.claude/skills/cua-driver` — `SKILL.md`, `MACOS.md`
(no-foreground contract, menu nav), and `WEB_APPS.md` (Chromium/WebKit/Electron quirks).
Read those for edge cases beyond what the browse skill covers.

## Uninstall

```bash
claude mcp remove cua-computer-use -s user
cua-driver skills uninstall
rm -rf /Applications/CuaDriver.app ~/.local/bin/cua-driver
```
