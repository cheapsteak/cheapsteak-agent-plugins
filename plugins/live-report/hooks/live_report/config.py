"""Three-layer config: plugin default < machine-wide < worktree.

Every layer is optional and every layer is best-effort: a malformed file is
ignored rather than fatal, because this runs inside a hook that must never be
the reason a turn cannot finish.
"""

from __future__ import annotations

import json
from pathlib import Path

CONFIG_KEYS = frozenset({"cap_lines", "floor_turns"})


def _read(path: Path) -> dict:
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    return {k: v for k, v in data.items() if k in CONFIG_KEYS and isinstance(v, int)}


def load_config(
    worktree_root: Path, *, plugin_root: Path, home: Path
) -> dict[str, int]:
    merged: dict[str, int] = {}
    for layer in (
        plugin_root / "config.default.json",
        home / ".config" / "live-report" / "config.json",
        worktree_root / ".agent" / "live-report" / "config.json",
    ):
        merged.update(_read(layer))
    # Every key here is a positive count, and both are hand-edited in a
    # local file with no review step. `floor_turns: 0` would make the
    # floor fire on the turn the model just stamped — a block every single
    # turn, from a plausible typo — and `cap_lines: 0` would warn about every
    # document that exists. Clamp rather than reject: a hook that refuses a
    # config is a hook that stops working.
    return {k: max(1, v) for k, v in merged.items()}
