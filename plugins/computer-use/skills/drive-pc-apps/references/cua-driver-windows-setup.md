# cua-driver setup (Windows)

[cua-driver](https://github.com/trycua/cua/tree/main/libs/cua-driver) is a background computer-use
tool that drives apps via UI Automation + screen capture and exposes an MCP server, so Claude Code
can read and operate any window without stealing focus or moving the cursor.

If `mcp__cua-computer-use__*` tools are already available, it's installed — skip to "Verify."

## Install (PowerShell, no admin)
```powershell
irm https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/scripts/install.ps1 | iex
```
Installs the `cua-driver` CLI under `%LOCALAPPDATA%\Programs\Cua\cua-driver\bin`.

## Register the MCP server
The driver prints the exact command via `cua-driver mcp-config --client claude`. It is (note: use
JSON that your shell quotes correctly — on PowerShell the single-quote form from `mcp-config` may
need adjusting):
```bash
claude mcp add-json cua-computer-use '{"command":"C:/Users/<you>/AppData/Local/Programs/Cua/cua-driver/bin/cua-driver.exe","args":["mcp","--claude-code-computer-use-compat"]}'
```
Verify it registered: `claude mcp list` → `cua-computer-use` should be `Connected`. New tools appear
after a fresh Claude Code session / reconnect.

## Permissions
Windows needs **no** Accessibility/Screen-Recording grants (unlike macOS). `cua-driver doctor`
should report UI Automation OK and EnumWindows working. The driver runs in your interactive desktop
session; `cua-driver autostart enable` keeps the daemon running across logons.

## Verify
```bash
cua-driver status        # daemon running
cua-driver doctor        # capabilities
```
From Claude Code, `mcp__cua-computer-use__get_screen_size` should return your display size + scale.

## For foreground control of legacy apps
Reading + standard-control clicks work out of the box. Driving Win32 menus / custom-drawn panes
needs the UIAccess worker — see `uiaccess-foreground-setup.md`.
