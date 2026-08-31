"""Hook-owned counters. Best-effort; a lost state file costs one extra nudge.

`owner_session` is the ownership record that makes a session RESTART inside a
worktree survivable. Without it the only evidence of who owns the document is
the stamp, every non-matching session id reads as a live foreign owner, and the
first restart — the normal case — freezes the document permanently: never
stale, never blocked, and forbidden from writing the one update that would
repair it. SessionStart claims ownership outright (a session start in this
worktree IS the takeover event); Stop keeps it, and reports a foreign owner
only when the recorded owner and the document stamp AGREE with each other and
disagree with this session, which is the shape two genuinely-live sessions
make.
"""

from __future__ import annotations

import json
from pathlib import Path

DEFAULT = {
    "turn": 0,
    "head_at_last_write": "",
    "open_questions": [],
    "owner_session": "",
}


def load(path: Path) -> dict:
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return dict(DEFAULT)
    if not isinstance(data, dict):
        return dict(DEFAULT)
    merged = dict(DEFAULT)
    merged.update({k: v for k, v in data.items() if k in DEFAULT})
    return merged


def save(path: Path, data: dict) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data))
    except OSError:
        pass
