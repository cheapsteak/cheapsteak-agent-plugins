---
name: browse
description: Browse a web app in the user's real, logged-in browser — "check the app", "open the site", "look at the UI", "verify this page", "browse", or diagnose frontend behavior. Routes to the cua-driver computer-use tools.
---

# Browse

Browsing a web app = driving the user's **real, already-open browser** with the **cua-driver**
MCP tools (`mcp__cua-computer-use__*`). You inherit their existing login (no auth dance) and don't
steal focus. Hit a login wall? Ask them to log in in that window, then continue.

$ARGUMENTS: URL or what to investigate (optional — ask if not provided).

- **Tools missing from your session?** Install + register + grant permissions:
  [references/cua-driver-setup.md](references/cua-driver-setup.md).
- **How to actually drive it** (snapshot→act→verify loop, reading via screenshot / AX tree / DOM,
  clicking by `element_index`, Chromium/Electron quirks): use the bundled **`cua-driver`** skill
  (`~/.claude/skills/cua-driver`). Don't re-derive it here — that skill is the source of truth.
