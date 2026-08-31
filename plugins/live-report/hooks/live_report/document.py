"""Parsing and rendering of the live document's machine-readable parts."""

from __future__ import annotations

import re
from dataclasses import dataclass

STAMP_TEMPLATE = "last updated: {timestamp} · turn {turn} · session {session_id}"
_STAMP_RE = re.compile(
    r"last updated:\s*(?P<ts>\S+)\s*·\s*turn\s+(?P<turn>\d+)\s*·\s*session\s+(?P<sid>\S+)"
)

DERIVED_BEGIN = "<!-- live-report:derived:begin -->"
DERIVED_END = "<!-- live-report:derived:end -->"

TAGS = frozenset({"DECISION", "BLOCKED", "PARKED"})


@dataclass(frozen=True)
class Stamp:
    timestamp: str
    turn: int
    session_id: str


def parse_stamp(text: str) -> Stamp | None:
    """Return the LAST stamp in the document, or None.

    Last rather than first: the document is rewritten whole, but a promotion
    pass can leave an older stamp quoted in a summary line. The newest one is
    the one that describes the file.
    """
    matches = list(_STAMP_RE.finditer(text or ""))
    if not matches:
        return None
    m = matches[-1]
    return Stamp(
        timestamp=m.group("ts"), turn=int(m.group("turn")), session_id=m.group("sid")
    )


def render_derived_block(
    facts: dict, *, turn: int, timestamp: str, log_link: str
) -> str:
    """The hook-owned block.

    It carries `derived:`, never `last updated:` — the stamp the hook CHECKS
    must not be written by the hook, or the exit condition self-satisfies and
    enforcement is silently dead.
    """
    branch = facts.get("branch", "(unknown)")
    sha = facts.get("sha", "(unknown)")
    dirty = facts.get("dirty", "(unknown)")
    return "\n".join(
        [
            DERIVED_BEGIN,
            f"`{branch}` at `{sha}` — {dirty}",
            f"Record: [{log_link}]({log_link})",
            f"derived: {timestamp} · turn {turn}",
            DERIVED_END,
        ]
    )


def replace_derived_block(text: str, block: str) -> str:
    start = text.find(DERIVED_BEGIN)
    end = text.find(DERIVED_END)
    if start == -1 or end == -1 or end < start:
        return f"{block}\n\n{text}"
    return text[:start] + block + text[end + len(DERIVED_END) :]


# The "Waiting on you" section title, in any shape the model is likely to
# render it: an ATX heading, a bold line, a numbered or bulleted list item, or
# any combination. SKILL.md ships one exact template, but a parser that
# recognises exactly one shape returns [] for every other one — and [] is
# indistinguishable from "this worktree needs nothing", which is total silence
# in the one place silence is the signal.
def content_line_count(text: str) -> int:
    """Lines of the live document that count against `cap_lines`.

    The hook-owned derived block is excluded — it is bookkeeping the hook
    itself sizes, and counting it would charge the model for a section it does
    not write and cannot shrink. Blank lines are excluded too: the skeleton is
    six blank-separated sections, so counting separators would spend a third of
    the budget on whitespace and make the cap fire on documents that are
    nowhere near the bloat it exists to catch.
    """
    body = text or ""
    start = body.find(DERIVED_BEGIN)
    end = body.find(DERIVED_END)
    if start != -1 and end != -1 and end >= start:
        body = body[:start] + body[end + len(DERIVED_END) :]
    return sum(1 for line in body.split("\n") if line.strip())


_WAITING_RE = re.compile(
    r"^[ \t]*(?:[-*+][ \t]+)?(?:\d+[.)][ \t]+)?(?:#{1,6}[ \t]*)?"
    r"\*{0,2}[ \t]*waiting on you[ \t]*\*{0,2}[ \t]*:?[ \t]*$",
    re.IGNORECASE | re.MULTILINE,
)

# A question line, with the same tolerance: `Q7 —`, `- Q7 —`, `1. Q7 —`,
# `**Q7** —`, `### Q7 —`, and combinations.
_QUESTION_RE = re.compile(
    r"^[ \t]*(?:[-*+][ \t]+)?(?:\d+[.)][ \t]+)?(?:#{1,6}[ \t]+)?\*{0,2}Q(\d+)\b"
)

# What ENDS the section. A heading or a bold-only line starts the next one —
# but a question rendered AS a heading (`### Q7 —`) must not end the section it
# lives in, so the question test is applied first and always wins.
_HEADING_RE = re.compile(r"^[ \t]*#{1,6}[ \t]+\S")
_BOLD_TITLE_RE = re.compile(
    r"^[ \t]*(?:[-*+][ \t]+)?(?:\d+[.)][ \t]+)?\*\*[^*]+\*\*[ \t]*:?[ \t]*$"
)


def open_questions(text: str) -> list[int]:
    """The Q-numbers currently open, ascending.

    Scoped to the "Waiting on you" section only: an answered question lives in
    the log with its answer, and a Q-number quoted anywhere else is a reference,
    not an open ask.
    """
    m = _WAITING_RE.search(text or "")
    if not m:
        return []
    found: set[int] = set()
    for line in text[m.end() :].split("\n"):
        q = _QUESTION_RE.match(line)
        if q:
            found.add(int(q.group(1)))
            continue
        if _HEADING_RE.match(line) or _BOLD_TITLE_RE.match(line):
            break
    return sorted(found)
