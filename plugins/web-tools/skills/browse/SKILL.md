---
name: browse
description: Browse any web app in a real browser using Playwright CLI. Use when asked to "check the app", "open the site", "look at the UI", "verify this page", "browse", or diagnose frontend behavior. General-purpose — not tied to any specific app.
---

# Browse

Open any web app in a real browser using `playwright-cli` to diagnose issues, verify features, or explore UI behavior.

$ARGUMENTS: URL or description of what to investigate (optional — will ask if not provided)

## Environment setup

**REQUIRED**: Set these env vars before every `bunx @playwright/cli` command. The nix-shell `$TMPDIR` path is too long for Unix domain sockets (macOS limit: 104 bytes), causing `EINVAL` errors.

```bash
export TMPDIR=/tmp
export PLAYWRIGHT_DAEMON_SOCKETS_DIR=/tmp/pw-cli
```

## Workflow

### 1. Open browser

```bash
export TMPDIR=/tmp PLAYWRIGHT_DAEMON_SOCKETS_DIR=/tmp/pw-cli
bunx @playwright/cli open
```

### 2. Navigate

```bash
bunx @playwright/cli goto <url>
```

### 3. Handle authentication

Check if the page loaded as expected or if you hit a login wall:

```bash
bunx @playwright/cli snapshot
```

**If you see a login page or auth wall:**

1. Tell the user: "The app requires authentication. I'll open the login page so you can log in manually."
2. Take a snapshot to identify the login form elements
3. Ask the user for credentials or have them type directly — use `click`/`fill` to interact with the login form interactively
4. After login succeeds, save the auth state:
   ```bash
   bunx @playwright/cli state-save /tmp/browse-auth-<domain>.json
   ```
5. Tell the user the state file path so future sessions can skip login

**If you have a saved auth state:**

```bash
bunx @playwright/cli state-load /tmp/browse-auth-<domain>.json
bunx @playwright/cli goto <url>
bunx @playwright/cli snapshot
```

If the saved state is stale (login page appears again), tell the user and redo interactive login.

### 4. Explore and diagnose

Use `snapshot` to see the current page state as an accessibility tree:

```bash
bunx @playwright/cli snapshot
```

The snapshot returns element references (e.g., `e15`, `e42`) that you can use in subsequent commands:

```bash
bunx @playwright/cli click e15
bunx @playwright/cli fill e42 "search text"
bunx @playwright/cli snapshot
```

### 5. Clean up

```bash
bunx @playwright/cli close
```

## Command Reference

### Navigation
| Command | Description |
|---------|-------------|
| `goto <url>` | Navigate to URL |
| `go-back` | Browser back |
| `reload` | Reload page |
| `snapshot` | Get page accessibility tree with element refs |
| `screenshot` | Save screenshot of current page |

### Interaction
| Command | Description |
|---------|-------------|
| `click <ref>` | Click an element |
| `fill <ref> <text>` | Fill a text input |
| `select <ref> <val>` | Select dropdown option |
| `hover <ref>` | Hover over element |
| `press <key>` | Press keyboard key (e.g., `Escape`, `Enter`) |

### Inspection
| Command | Description |
|---------|-------------|
| `console` | View browser console messages |
| `network` | List network requests since page load |
| `eval <js>` | Evaluate JavaScript in page context |
| `localstorage-list` | List all localStorage entries |
| `cookie-list` | List all cookies |

### Session
| Command | Description |
|---------|-------------|
| `state-load <file>` | Load auth state from file |
| `state-save <file>` | Save current state to file |
| `tab-list` | List open tabs |
| `tab-new <url>` | Open new tab |
| `close` | Close browser |

## Session persistence

All `bunx @playwright/cli` commands share state within a session. If your session dies or you open a new terminal, just re-run `open` and `state-load`.

## Alternative: cua-driver (computer-use)

When you need to drive the user's **already-open** browser (inheriting their existing login, no focus-steal),
or when Playwright CLI can't reach the app (Electron, native shells, OAuth popups that break headed
Playwright), reach for **cua-driver** instead. It snapshots the accessibility tree of any running GUI app
and clicks/types by `element_index` or pixel coords.

- Setup (install CLI, register MCP, grant accessibility permissions):
  [references/cua-driver-setup.md](references/cua-driver-setup.md).
- Once installed, use the bundled `cua-driver` skill (`~/.claude/skills/cua-driver`) for the
  snapshot→act→verify loop — that's the source of truth for driving it.

Default to Playwright CLI for general web browsing; switch to cua-driver only when you need one of the
properties above.

## Self-healing

**When something doesn't work as described in this skill, fix the skill.**

After resolving any issue not already covered in Troubleshooting, append the problem and solution to the Troubleshooting section below. This keeps the skill accurate over time.

Similarly, if you discover a working auth flow for a specific app (OAuth redirect, SSO, API token injection, etc.), add it to the App-Specific Auth section below so future sessions can reuse it.

## App-Specific Auth

<!-- Add entries here as you discover auth flows for specific apps. Format:

### <app-name> (<domain>)
**Auth type**: OAuth / SSO / Basic / Token / etc.
**Steps**:
1. ...
**State file**: /tmp/browse-auth-<domain>.json
**Token lifetime**: ~X hours
-->

_No app-specific auth flows documented yet. When you successfully authenticate to a new app, add the steps here._

## Troubleshooting

### "EINVAL: invalid argument" on socket path
The nix-shell `$TMPDIR` path is too long for Unix domain sockets (macOS limit: 104 bytes). Override **both** env vars:

```bash
export TMPDIR=/tmp
export PLAYWRIGHT_DAEMON_SOCKETS_DIR=/tmp/pw-cli
```

### Browser doesn't open
Run `bunx @playwright/cli install-browser` to ensure Chromium is installed.

### Do NOT use MCP Playwright tools
The MCP tools (`mcp__playwright__browser_*`) open a separate browser context that doesn't share state with the CLI session. Always use `bunx @playwright/cli` commands.
