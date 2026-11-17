# macos-ops

macOS sysadmin.

## Skills

- **diagnose-memory** — Diagnose macOS memory usage and identify what's consuming RAM. Use when the system is slow, swap is high, or Activity Monitor shows suspicious numbers.
- **1password-access** — Read a secret from 1Password via the `op` CLI without leaking it into the transcript.
- **migrate-mac** — Move a developer Mac to a new one with Migration Assistant: what to delete first (dependency folders, package stores, build output, sparse VM disk images), what recreates those folders while you delete, and what to fix on the new Mac (Nix reinstall, Okta Verify, Xcode first launch, toolchains, broken links).

## Requirements

- macOS (skills use `vm_stat`, `top`, `ps`, etc.)
