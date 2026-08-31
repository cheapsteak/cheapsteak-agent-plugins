# live-report

A live, per-worktree status document that the session **cannot forget to
update**, because a `Stop` hook checks it at the end of every turn.

## The problem

Run three or four agent sessions at once and the failure isn't that any of them
does bad work — it's that you can't tell what any of them is doing without
reading it. You come back to a terminal, the useful part has scrolled away, and
the last line on screen is a question whose entire context is gone. Answering it
means re-reading the transcript, or asking the session to explain itself again.

Asking the model to "keep a status file updated" doesn't fix this. It works for
a while, then it doesn't, and nothing tells you when it stopped — a stale
document is indistinguishable from a quiet worktree. The document rots exactly
when you most need it: during the long, messy stretch of work that produced the
question you're staring at.

## The shape of the fix

**Two files**, both under `.agent/live-report/` at the repository root:

| File | What it is |
|---|---|
| `status.md` | The **live document**. Short, capped, rewritten **whole** on every update. Holds only what is true *right now*. |
| `status-log.md` | The **record**. Prepend-only, newest entry first. Holds only what is *finished*. |

The two-file split is what lets the live document stay short without losing
anything. History has somewhere to go, so the live document is free to forget:
when something finishes it is **moved** — cut from `status.md`, prepended to
`status-log.md` — never copied. Nothing is ever in both files, so the two can't
contradict each other.

The live document is emitted **whole, section by section**, never patched
line-by-line. That's the invariant that makes self-contradiction structurally
impossible: a document where a header claims one thing and a table further down
claims another is the normal outcome of incremental edits, and a whole-section
rewrite can't drift from itself.

Its sections, in order: a hook-owned derived block, **Waiting on you**, **Where
things stand**, **Now**, **Blocked**, **The tree**.

## Why a hook, not a prompt

The freshness rule is enforced at turn end by a `Stop` hook, not asked for in
the skill's prose. A prompt that says "remember to update the report" degrades
silently; a hook that blocks the turn does not.

The hook blocks when the document has no stamp, has fallen `floor_turns` turns
behind, or when `HEAD` has moved since the last write. It warns — never blocks
— when the document is over `cap_lines`, because going over the cap is
sometimes the honest answer (a long **Blocked** list during an outage is a real
state) and what matters is that it's a *noticed* choice.

Three things make the enforcement real rather than decorative:

- **The hook writes `derived:` and never `last updated:`.** The stamp the hook
  *checks* must be written by the model. A hook that wrote the stamp it checks
  would pass its own test forever — enforcement that looks alive and does
  nothing.
- **Ownership is recorded outside the document.** Sessions restart inside a
  worktree constantly, and a restart leaves a document stamped by an id that
  will never appear again. Treating that as "another session owns this" freezes
  the document permanently on the happy path. So a session start *claims*
  ownership; the only thing reported as concurrent is the shape two genuinely
  live sessions make — the recorded owner is somebody else **and** that same
  somebody wrote the document last. In that one case the hook refuses to write
  even its own block.
- **The hooks state the session id out loud.** The stamp requires it and the
  model has no other source: no environment variable carries it, and the id
  already in the document belongs to whoever wrote last. A guessed id reads as
  a foreign session on every later turn and kills the guard quietly.

The hook never blocks a turn for its own reasons. Every failure path — a
malformed config, a broken sibling module, an unreadable document — exits 0 and
does nothing. It also bails out for subagents before touching any state.

## What you actually see

One line, printed only when the set of open questions **changes**:

```
⏸ waiting on you — Q7, Q9 — /path/to/worktree/.agent/live-report/status.md
```

Silence means this worktree needs nothing from you. Question numbers are
monotonic per worktree and never reused — an answered question moves to the log
with its answer, and gaps in the numbering (`Q7`, `Q9`, `Q12`) are correct.
Renumbering would create a race where an answer you thought about for five
minutes lands on a different question than the one you read.

## The three verbs

| Verb | What it does |
|---|---|
| `/live-report` | Turn it on **here**. Creates both files and the `.agent/live-report/on` marker. |
| `/live-report off` | Turn it off. Deletes **only** the marker — both files are left untouched, because they're the record of what happened. |
| `/live-report update` | Rewrite the live document now, whole. |

There is deliberately no `status` verb: the status *is* the file.

### Turning it off

Three levels, from narrowest to widest:

| Scope | How |
|---|---|
| This worktree | `/live-report off`, or just `rm .agent/live-report/on` from any shell |
| Everywhere, reversibly | `claude plugin disable live-report@cheapsteak-agent-plugins` |
| Everywhere, permanently | `claude plugin uninstall live-report@cheapsteak-agent-plugins` |

The per-worktree switch is a plain file on purpose. If a session is wedged or the
hook is misbehaving, `rm .agent/live-report/on` stops it immediately — you don't
need a working agent to turn it off.

`disable` genuinely stops the hooks from running; that was measured rather than
assumed, with a probe plugin whose `Stop` hook logged on every turn (it logged
while enabled, and did not log after `disable`).

While the plugin is installed and enabled, its hooks do run in every worktree —
but one that has never been turned on costs a single file-existence test per
turn end, and nothing else.

## Install

```
/plugin marketplace add https://github.com/cheapsteak/cheapsteak-agent-plugins.git
/plugin install live-report@cheapsteak-agent-plugins
```

Restart Claude Code afterwards — plugins added mid-session don't load.

Installing arms the hooks but turns nothing on. Every worktree is opt-in: until
`.agent/live-report/on` exists there, both hooks are a single `[ -f ]` test and
return. Run `/live-report` in a worktree to opt it in.

## Configuration

Three layers, later overriding earlier:

1. `<plugin>/config.default.json` — shipped defaults
2. `~/.config/live-report/config.json` — machine-wide
3. `.agent/live-report/config.json` — this worktree

| Key | Default | Meaning |
|---|---|---|
| `cap_lines` | 40 | Soft cap on the live document's own content lines (the hook-owned derived block and blank lines don't count). Warns; never blocks. |
| `floor_turns` | 10 | Turns the stamp may fall behind before the hook blocks. |

Every layer is optional, and a malformed one is ignored rather than fatal.
Values are clamped to at least 1: `floor_turns: 0` would block on the very turn
the model just stamped, from a plausible typo.

## Why `.agent/` and not `.claude/`

The hooks here are Claude Code-specific, but the *document convention* isn't.
`.agent/live-report/status.md` is a plain markdown file with a documented shape,
and a session running under any other agent harness can read it, write it, and
follow the same rules — the enforcement is what's harness-specific, not the
artifact. Putting it under `.claude/` would have implied otherwise and made the
convention harder to adopt anywhere else.

You'll probably want `.agent/` in your `.gitignore`, unless you'd rather commit
the report.

## Tests

There's no CI in this repo, so run them by hand from the repository root:

```bash
python3 -m unittest discover -s plugins/live-report/tests -p 'test_*.py'
```

No dependencies beyond the standard library and `git`.

## Status

New, and not yet battle-tested. The design is deliberate but the mileage isn't
there yet — expect to find edges.
