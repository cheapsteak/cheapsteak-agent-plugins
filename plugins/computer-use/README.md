# computer-use

Drive native desktop GUI apps via cua-driver (the `cua-computer-use` MCP) — read the screen, click,
type, navigate — reliably, including DPI-unaware legacy Windows apps.

## Skills

- **drive-pc-apps** — Operate Windows desktop apps through cua-driver. Centerpiece: the **DPI
  click-offset fix** (pixel clicks land at `1/scale` against DPI-unaware legacy apps on scaled
  displays — compensate by `× scale_factor`), plus headless foreground control (UIAccess worker),
  re-query-geometry-every-time robustness, and reading data out via UIA / print-to-PDF.

## Requirements

- Windows, with the `cua-computer-use` MCP (cua-driver) connected. Setup:
  `skills/drive-pc-apps/references/cua-driver-windows-setup.md`.
- Foreground control of legacy menus/panes needs the signed UIAccess worker:
  `skills/drive-pc-apps/references/uiaccess-foreground-setup.md`.

## Relationship to `web-tools`

`web-tools/browse` covers browser automation (Playwright CLI, with cua-driver as an
already-open-browser alternative). `computer-use` is for **native desktop apps** — the things a
browser driver can't reach.
