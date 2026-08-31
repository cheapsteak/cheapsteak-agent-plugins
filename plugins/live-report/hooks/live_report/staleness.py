"""The block's exit condition, as a pure function.

The ONLY thing that clears a block is the document's own stamp naming the
current turn. Everything else is a reason to raise one.
"""

from __future__ import annotations

from dataclasses import dataclass

from .document import Stamp


@dataclass(frozen=True)
class Verdict:
    stale: bool
    reason: str
    foreign_session: bool


def evaluate(
    *,
    stamp: Stamp | None,
    current_turn: int,
    current_head: str,
    head_at_last_write: str,
    floor_turns: int,
    session_id: str,
    owner_session: str,
) -> Verdict:
    if stamp is None:
        return Verdict(True, "status.md has no stamp", False)

    if (
        owner_session
        and owner_session != session_id
        and stamp.session_id == owner_session
    ):
        # Two sessions are genuinely live at once: the state file's recorded
        # owner is somebody else AND that same somebody wrote the document
        # last. Report; never overwrite.
        #
        # A bare `stamp.session_id != session_id` is NOT this test, and the
        # difference is the whole point. Sessions restart inside a worktree
        # constantly, and a restart leaves exactly that mismatch — so treating
        # it as a live foreign owner froze the document at the first restart,
        # permanently and on the happy path. The recorded owner is what
        # separates "somebody else is writing right now" from "somebody else
        # WAS writing, and is gone".
        return Verdict(False, "", True)

    if stamp.turn >= current_turn:
        return Verdict(False, "", False)

    if current_turn - stamp.turn >= floor_turns:
        return Verdict(
            True,
            f"status.md is stamped turn {stamp.turn}; it is now turn {current_turn} "
            f"({floor_turns} turns without a write)",
            False,
        )

    if current_head != head_at_last_write:
        return Verdict(
            True,
            f"status.md is stamped turn {stamp.turn}; HEAD has moved since "
            f"({head_at_last_write[:7]} to {current_head[:7]})",
            False,
        )

    return Verdict(False, "", False)
