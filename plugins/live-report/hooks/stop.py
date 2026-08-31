#!/usr/bin/env python3
# plugins/live-report/hooks/stop.py
"""Stop hook: keep .agent/live-report/status.md honest.

POSTURE, in priority order:
  1. Never be the reason a turn cannot finish. Every failure path exits 0,
     including a broken sibling module — the live_report imports are
     deferred into main()'s own try/except rather than sitting at module
     level, so a broken import degrades to a silent no-op instead of a
     traceback on every turn.
  2. Never fire for a subagent — Stop/SubagentStop delivery for subagents
     is unreliable in several ways, so bail on every known subagent-context
     signal rather than trusting one, before any state or document I/O
     happens.
  3. Only the model's own `last updated:` stamp clears a block. This hook
     writes `derived:` and never `last updated:`; writing the stamp it checks
     would make the exit condition self-satisfying and silently kill the guard.
  4. Never write into a document another session owns — but "another
     session" means one that is genuinely LIVE, not merely one whose id
     differs. Sessions restart inside a worktree constantly; ownership is
     recorded in the state file and claimed by whoever is running, so a
     restart takes over instead of freezing the document forever.
  5. Say the session id out loud. The model has no other source for it — it is
     not an environment variable and it is not in the document except in a
     stamp that may name a session that is gone — so a block that asks for a
     stamp must name the exact id to stamp with, or the model guesses, the
     guess reads as a foreign session, and the guard is dead from then on.
"""

from __future__ import annotations

import datetime as _dt
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

DOC = ".agent/live-report/status.md"
LOG_LINK = "./status-log.md"
STATE = ".agent/live-report/state.json"
MARKER = ".agent/live-report/on"


def main(payload: dict, *, root: Path, plugin_root: Path, home: Path) -> dict | None:
    if payload.get("agent_id") or payload.get("agent_type"):
        return None
    if payload.get("hook_event_name") == "SubagentStop":
        return None
    if payload.get("stop_hook_active"):
        return None

    session_id = payload.get("session_id")
    if not session_id:
        return None

    # This worktree has not opted in — a single existence test is the whole
    # cost, checked before any other I/O (state load, document read). Created
    # by `/live-report`, removed (only this file) by `/live-report off`.
    if not (root / MARKER).exists():
        return None

    doc_path = root / DOC
    if not doc_path.exists():
        return None

    try:
        from live_report import facts, state
        from live_report.config import load_config
        from live_report.document import (
            content_line_count,
            open_questions,
            parse_stamp,
            render_derived_block,
            replace_derived_block,
        )
        from live_report.staleness import evaluate
    except Exception:
        # Priority 1: a broken sibling module degrades to a silent no-op
        # rather than a traceback on every turn.
        return None

    cfg = load_config(root, plugin_root=plugin_root, home=home)
    st = state.load(root / STATE)
    previous_turn = int(st.get("turn", 0))
    st["turn"] = previous_turn + 1

    text = doc_path.read_text()
    stamp = parse_stamp(text)
    repo = facts.collect(root)
    head = repo.get("sha", "")

    # Bookkeeping only: compare against the counter as it stood BEFORE this
    # invocation incremented it, not after — otherwise a model that stamps
    # exactly the turn named in the block reason can never satisfy this
    # check in steady state, head_at_last_write freezes at its first value,
    # and every subsequent HEAD move blocks a fully compliant model forever.
    if stamp is not None and stamp.turn >= previous_turn:
        st["head_at_last_write"] = head

    verdict = evaluate(
        stamp=stamp,
        current_turn=st["turn"],
        current_head=head,
        head_at_last_write=st.get("head_at_last_write", ""),
        floor_turns=int(cfg.get("floor_turns", 10)),
        session_id=session_id,
        owner_session=str(st.get("owner_session", "")),
    )

    # Claim (or keep) ownership on every turn this session is allowed to write.
    # This is what makes a restart survivable: the recorded owner tracks
    # whoever is actually running, so the NEXT session's Stop compares against
    # a session that ran, not against a stamp that may be days old.
    if not verdict.foreign_session:
        st["owner_session"] = session_id

    result: dict = {}

    # The ONLY thing the human sees from this plugin: a stable marker plus a
    # clickable path, printed only when the open-question set actually
    # changes. Silence is the signal that nothing needs attention.
    waiting = open_questions(text)
    previous = st.get("open_questions") or []
    if waiting and waiting != previous:
        # Name EVERY currently open question, not a selected one. The
        # trigger for printing is "the open set changed", so the honest
        # payload is the set itself — picking a single representative
        # (lowest-numbered, or newest) is lossy in whichever direction it
        # doesn't pick: lowest-open hides that a new question arrived,
        # newest hides that an older one is still pending. The user is
        # triaging across many worktrees and needs the whole set.
        names = ", ".join(f"Q{n}" for n in waiting)
        result["systemMessage"] = f"⏸ waiting on you — {names} — {doc_path}"
    st["open_questions"] = waiting
    state.save(root / STATE, st)

    if verdict.foreign_session:
        # Never write into a document another session owns — not even the
        # hook-owned derived block.
        result["hookSpecificOutput"] = {
            "hookEventName": "Stop",
            "additionalContext": (
                f"Another session is live in this worktree and owns {DOC}: it is "
                "recorded as the owner AND it wrote the document last. Do not "
                "overwrite it — reconcile with that session, or defer. (This is "
                "NOT the ordinary case of a stamp naming an earlier session; a "
                "restart takes ownership and is told to write normally.)"
            ),
        }
        return result or None

    now = _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        doc_path.write_text(
            replace_derived_block(
                text,
                render_derived_block(
                    repo, turn=st["turn"], timestamp=now, log_link=LOG_LINK
                ),
            )
        )
    except OSError:
        pass

    # The cap is a WARNING, never a block: going over is permitted when going
    # over is right, it simply has to be a noticed choice. Enforcement here is
    # only ever the sentence below — but the sentence has to exist, or the
    # "forcing function for the whole design" is a rule in a prompt, which is
    # exactly what the first attempt had when it reached 708 lines.
    cap = int(cfg.get("cap_lines", 40))
    lines = content_line_count(text)
    over_cap = (
        f"{DOC} is {lines} lines against a cap of {cap} — promote the oldest "
        "items in *Where things stand* into a higher-altitude line, written "
        f"from the log's verbatim entries in {LOG_LINK}."
        if lines > cap
        else ""
    )

    if verdict.stale:
        result["decision"] = "block"
        result["reason"] = (
            f"{verdict.reason}. Update {DOC} and stamp turn {st['turn']} with "
            f"session {session_id}. Keep it under {cap} lines; move finished "
            f"items to {LOG_LINK} (newest first)."
        )
        if over_cap:
            result["reason"] += f" {over_cap}"
    elif over_cap:
        result["hookSpecificOutput"] = {
            "hookEventName": "Stop",
            "additionalContext": over_cap,
        }

    return result or None


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
        # Priority 1: never be the reason a turn cannot finish.
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(_run())
