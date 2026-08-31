#!/usr/bin/env python3
"""SessionStart hook: inherit the document, never fight the model.

SessionStart INFORMS; Stop ENFORCES. A session start is a bad moment to block,
and the first Stop finds the same staleness anyway — where blocking is safe and
already designed for.

It does take one WRITE, and only one: it claims ownership of the document in
the state file. A session start inside this worktree IS the takeover event —
sessions restart here constantly, and the alternative (treating every
non-matching stamp as a live foreign owner) freezes the document permanently at
the first restart. Claiming here is also why `Stop` can afford a narrow
foreign-owner test: by the time it runs, the recorded owner names a session
that actually started.

It also states this session's id outright. The model has no other source for
it — no environment variable carries it, and the only id in the document
belongs to whoever stamped last, which after a restart is a session that no
longer exists. Copying that one produces a stamp that reads as foreign forever.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

DOC = ".agent/live-report/status.md"
STATE = ".agent/live-report/state.json"
MARKER = ".agent/live-report/on"


def main(payload: dict, *, root: Path, plugin_root: Path, home: Path) -> dict | None:
    if payload.get("agent_id") or payload.get("agent_type"):
        return None

    # This worktree has not opted in — a single existence test is the whole
    # cost, checked before any other I/O. Created by `/live-report`, removed
    # (only this file) by `/live-report off`.
    if not (root / MARKER).exists():
        return None

    doc_path = root / DOC
    if not doc_path.exists():
        return None

    # plugin_root and home are accepted for signature parity with stop.py and are
    # deliberately unused; they keep the two hooks callable the same way.

    try:
        from live_report import facts, state
        from live_report.document import parse_stamp
    except Exception:
        # A broken sibling module degrades to a silent no-op rather than a
        # traceback at session start.
        return None

    session_id = payload.get("session_id") or ""
    stamp = parse_stamp(doc_path.read_text())
    head = facts.collect(root).get("sha", "")

    # The one write. Best-effort, like every other state write in this plugin:
    # a lost claim costs one extra foreign-owner report, never a wedge.
    if session_id:
        st = state.load(root / STATE)
        st["owner_session"] = session_id
        state.save(root / STATE, st)

    lines = [f"This worktree keeps a live report at {DOC}. Read it before you start."]
    if session_id:
        lines.append(
            f"This session's id is {session_id} — that is the value to write in the "
            "stamp's `session` field. Never invent one and never copy the id out of "
            "an existing stamp."
        )
    if stamp is None:
        lines.append(
            "It has no stamp — reconcile it against the working tree and stamp it."
        )
    else:
        lines.append(
            f"It was last stamped turn {stamp.turn} by session {stamp.session_id}."
        )
        if stamp.session_id and session_id and stamp.session_id != session_id:
            lines.append(
                "That is a DIFFERENT session, and this session has now claimed "
                "ownership of the document — so write it normally and stamp it with "
                "your own id above, unless Stop reports that another session is live. "
                "(Two sessions genuinely running at once in one worktree is the rare "
                "case, and Stop reports that separately.)"
            )
    if head:
        lines.append(
            f"HEAD is now {head}. If reality has moved past the report, "
            "reconciling it is your first act."
        )

    return {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": " ".join(lines),
        }
    }


def _run() -> int:
    try:
        payload = json.load(sys.stdin)
        root = Path(payload.get("cwd") or os.getcwd())
        plugin_root = Path(
            os.environ.get("CLAUDE_PLUGIN_ROOT", Path(__file__).resolve().parents[1])
        )
        out = main(payload, root=root, plugin_root=plugin_root, home=Path.home())
        if out:
            print(json.dumps(out))
    except Exception:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(_run())
