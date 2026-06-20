---
name: stacked-prs
description: Manage a PR stacked on another unmerged branch, and re-point it onto main after the base merges. Use when the user says "stack this PR", "restack", "re-point the PR base", "rebase onto main after the base merged", or has a PR whose base branch just merged.
---

# Stacked PRs

A stacked PR targets another open branch as its base (`gh pr create --base <branch>`), so its diff shows only your commits, not the base's.

## Restack onto main after the base merges

A merge queue rebases as it merges, so the base's commits land on `main` with **new SHAs** — the old base tip is no longer an ancestor of `main`, and a plain `git rebase origin/main` would try to replay the base's commits too. Cut at the old base tip with `--onto`:

```bash
git fetch origin
# OLD_BASE = the base branch's tip SHA from when you stacked
git rebase --onto origin/main <OLD_BASE_SHA> <your-branch>
gh pr edit <PR> --base main
git push --force-with-lease
```

This replays only your commits onto `main`. Resolve any conflict against `main`'s version (the base may have been tweaked before merging). Verify clean:

```bash
git rev-list --count HEAD..origin/main                                   # 0 = not behind
git merge-tree $(git merge-base HEAD origin/main) HEAD origin/main        # no conflict hunks
```

Right after the base swap GitHub may briefly report the PR `DIRTY` while it recomputes — re-check; it settles to `MERGEABLE`/`BLOCKED`.
