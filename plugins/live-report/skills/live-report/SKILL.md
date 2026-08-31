---
name: live-report
argument-hint: "[off|update]"
description: Keep a live, per-worktree status report at .agent/live-report/status.md that this session rewrites whole on every update, plus a prepend-only record of finished work at .agent/live-report/status-log.md. Three verbs — `/live-report` (turn on here), `/live-report off` (turn off), `/live-report update` (rewrite now). Use whenever a person invokes /live-report, or a Stop-hook block names status.md and asks you to update it.
---

# live-report

Two files, both under `.agent/live-report/` at the repository root.
`.agent/live-report/status.md` is the **live document** — short, capped,
and always rewritten **whole**. It holds only what is true **right now**.
`.agent/live-report/status-log.md` is the **record** — **prepend-only, newest
entry first** — and holds only what is **finished**. The live document
links the log high up, so anyone who wants history has one click to it.

**The core invariant: every section is emitted whole, never partially
edited.** Never patch a line inside a section and leave the rest as it was —
regenerate the whole section (or the whole document) from what is true now.
This is what makes self-contradiction structurally impossible. A prior
attempt at this idea failed exactly this way: a header at the top of the
file claimed one version while a table 480 lines further down still claimed
another, because an edit had touched one and not the other. A whole-section
rewrite cannot drift from itself.

**Items move, they are never copied.** The moment something is finished, you
cut it from the live document and prepend it to the log. The move *is* the
deletion — there is no separate "now also delete it" step, and nothing is
ever in both files at once. If you find yourself writing the same fact into
both files, stop: you are copying, not moving.

## The document skeleton

Emit the live document's sections in this order:

1. The derived block (hook-owned, delimited by
   `<!-- live-report:derived:begin -->` / `<!-- live-report:derived:end -->`
   — see "The stamp" below; never hand-edit it)
2. **Waiting on you**
3. **Where things stand**
4. **Now** — the single thing in flight
5. **Blocked** — what is stuck, and on whom or what
6. **The tree** — the branching work structure: the active frontier plus one
   level down. The full tree lives in the log, not here.

Keep the section headings even when a section is empty — an empty **Blocked**
is a fact ("nothing is blocked"), not something to omit.

## The stamp

On every update, write this line yourself, in exactly this form (those are
middle dots, U+00B7, not hyphens or colons):

```
last updated: <ISO timestamp> · turn <N> · session <session id>
```

**The hook writes a separate `derived:` line inside the derived block, and it
never writes `last updated:`.** Do not conflate these two lines — they look
similar and sit near each other, but they have opposite authors and opposite
jobs. `derived:` is the hook's own bookkeeping, refreshed automatically every
turn regardless of what you write. `last updated:` is the stamp the hook
*checks* to decide whether the document is stale. If the hook ever wrote the
stamp it checks, the check would always pass — the block would look enforced
while doing nothing, and nobody would notice until the document had quietly
rotted for weeks.

### Where `<session id>` comes from

**The hook tells you, and it is the only source.** No environment variable
carries it, and you cannot see it in your own context.

- `SessionStart` injects a line naming this session's id explicitly ("This
  session's id is `s1_abc` — that is the value to write in the stamp's
  `session` field").
- Every `Stop` block that asks for an update names it too: "…stamp turn 25
  with session `s1_abc`."

**Never invent one, and never copy the id out of the stamp already in the
document.** That id belongs to whoever wrote last, which after a session
restart — the normal case in a worktree — is a session that no longer exists.
A stamp carrying a made-up or inherited id makes the hook read the document as
owned by somebody else on every later turn: it never goes stale, it never
blocks, the backstop dies silently, and all three surfaces then tell you not
to make the one write that would repair it. If you genuinely have no id from
either hook, write the stamp with the rest of the line correct and say in the
document that the id was unavailable — do not guess.

### If the stamp names a different session

Read it before you write, but do not treat every mismatch as a standoff.
Sessions restart inside a worktree constantly, and a restart leaves exactly
this mismatch. The hook distinguishes the two cases for you, using an
ownership record it keeps outside the document:

- **A restart** (the normal case) — `SessionStart` will have told you the
  document is now yours. Write it normally and stamp it with **your own** id.
- **A genuinely concurrent session** — the `Stop` hook says so explicitly
  ("Another session is live in this worktree and owns…"), and it refuses to
  write even its own derived block. That is the only case where you **stop and
  report instead of overwriting**. The report clears only when this session
  restarts (claiming ownership at the next `SessionStart`), or someone resets
  `.agent/live-report/state.json`.

## Waiting on you

**Write this section exactly like this** — heading shape and question shape
both. A hook parses it to decide whether to print anything at all to the
human, and a shape it cannot read is indistinguishable from "nothing is
waiting", which is silence in the one place where silence is the signal:

```markdown
## Waiting on you

Q7 — Should the retry budget be per-file or per-batch?
    Options: (A) per-file, simpler; (B) per-batch, matches how failures
    actually cluster; (C) both, gated on file count.
    Context: the uploader currently retries per-file, so a batch of 40 files
    can burn the whole budget on one bad file.
    Recommendation: B.

Q9 — Ship the migration behind a flag, or straight?
    Options: (A) flag; (B) straight.
    Context: the table is small and the change is additive.
    Recommendation: B.
```

`## Waiting on you` as its own heading line, and each question starting at
the beginning of a line as `Q<n> — `. Continuation lines are indented under
it. The parser tolerates bullets, numbering, bold and sub-headings around the
`Q<n>`, but **reproduce the template rather than relying on that** — the
tolerance is a safety net, not the contract.

Each item carries the question, its options, the preamble needed to answer it
cold, and your own recommendation. Someone must be able to answer it without
opening a terminal or reading anything else.

**Question numbers are monotonic per worktree and are never reused.** When a
question is answered, move it (whole, with its answer) to the log — it does
not stay in the live document, and its number does not get recycled onto a
new question. The live document's **Waiting on you** section therefore shows
only currently-open questions, keeping each one's original number — so seeing
`Q7`, `Q9`, `Q12` with no `Q8`, `Q10`, `Q11` in between is expected and
correct, not a bug to fix by renumbering.

**Never renumber to close a gap.** Renumbering creates a race: a human reads
"Q3" in their terminal, steps away to think about it, and while they're gone
the document gets rewritten and what used to be Q4 slides down to Q3. Their
answer now lands on the wrong question. A stable number is the only thing
that makes an answer given later still valid.

**What the human actually sees.** The hook that watches this document prints
the absolute path only when the set of open questions changes — and it names
every open question when it does, not just the newest one:

```
⏸ waiting on you — Q7, Q9 — <absolute path>
```

When nothing is waiting, or the set hasn't changed since the last time it was
printed, **nothing is printed at all**. Silence is the signal that this
worktree needs no attention right now — don't try to "helpfully" restate the
same open questions turn after turn; let the hook's own change-detection do
that job.

## The cap

`cap_lines` (default 40, see `config.default.json`) is a soft cap on the
**whole live document, excluding the hook-owned derived block** — the derived
block is bookkeeping, not content, and doesn't count against it. Blank lines
don't count either; the measure is non-empty lines of your own content.

**The hook measures it and tells you the real number** — "status.md is 58
lines against a cap of 40" — either on its own or riding along with a block.

**It's a warning, not a limit.** Going over the cap is allowed when going
over is the right call for what's true right now — a long **Blocked** list
during an incident is a real state, not a formatting failure. What matters is
that going over is a *noticed* choice, not something that crept up on you
because nothing was ever promoted. When the warning appears and going over is
*not* the right call, promote (below) — do not delete.

## Promotion

Promotion applies to **Where things stand** only — it is the section with the
altitude ladder, and the one that compresses. Don't promote out of **Blocked**
or **The tree**; those hold their own present-tense facts, not a compressible
history.

Promotion is **pressure-driven**: nothing gets promoted out of **Where things
stand** until the live document exceeds its cap. Only then do you take the
oldest item-level entries and lift them into a single higher-altitude line.

**Write that line from the log's verbatim entries — never from the existing
summary text already sitting in the live document.** Go back to the log,
read what was actually recorded when the item finished, and summarize
*that*. Re-summarizing your own prior summary compounds distortion silently
— each pass loses a little more of what actually happened, and there is no
error message when it does. The oldest content in the live document is also
the least-recently-checked, which is exactly the content most likely to have
quietly drifted from the truth if you keep shrinking it in place instead of
going back to source.

A summary is a **higher-altitude capture**, not compressed text. "Stabilised
ingest under concurrent load" is a summary. The same three sentences with
some words removed is not — it's still the play-by-play, just harder to
read.

## Tags

Use these tags, written exactly as shown (with the backticks and the em
dash), so they read consistently and stay greppable across both files:

- `` `DECISION —` `` for a call that's been made and won't be revisited
  without new information
- `` `BLOCKED —` `` for something stuck on an external dependency —
  another session, a human, an approval, infrastructure
- `` `PARKED —` `` for something deliberately set aside, not forgotten and
  not blocked, just not now

## The three verbs

There are exactly three, and no fourth:

- **`/live-report`** — turn it on, here, in this worktree. Create both
  files (a minimal live document with all six sections and an empty log)
  and the marker `.agent/live-report/on`, then print the absolute path to
  the live document.
- **`/live-report off`** — turn it off. Delete only the marker
  `.agent/live-report/on` so the hooks go back to a single `[ -f ]` test
  and stop watching, but **leave both files completely untouched** — they
  are the record of what happened here, and turning the feature off is not
  a reason to delete history.
- **`/live-report update`** — rewrite the live document right now, whole,
  following everything above.

**There is deliberately no `status` verb.** The status *is* the file — you
open it and read it. A separate status command would just be a worse copy of
the document that already exists.
