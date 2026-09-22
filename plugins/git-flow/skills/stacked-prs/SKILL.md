---
name: stacked-prs
description: Create, link, sync and merge a stack of PRs using GitHub's native stacked pull requests and the gh stack CLI. Use when the user says "stack this PR", "link these PRs into a stack", "restack", "re-point the PR base", "rebase onto main after the base merged", "gh stack", or has a PR whose base branch just merged.
---

# Stacked PRs

A **Stack** is an explicit object on GitHub, introduced with [native stacked pull requests](https://github.blog/changelog/2026-07-30-stacked-pull-requests-are-now-in-public-preview/) (public preview, 2026-07-30). It has its own id and UI, and it tells a reviewer which layer they are looking at.

**Pointing `gh pr create --base <branch>` at another open PR's branch does not create one.** That is the old implicit arrangement: the diff is scoped correctly, but GitHub sees two unrelated PRs, there is no stack UI, and none of the stack commands work on them. You have to say it is a stack.

## Prerequisite

```bash
gh extension install github/gh-stack      # not installed by default; safe to re-run
```

Every command below is from that extension. If it is not installed and installing it is not an option, jump to [Fallback: the manual `--onto` recipe](#fallback-the-manual---onto-recipe).

## Creating a stack

**Branches first, PRs later (the common case).** You opened PRs one at a time — `gh pr create --base <parent-branch>` each time — and now want GitHub to know they are a stack:

```bash
gh stack link <bottom-pr> <top-pr> [...]   # bottom-to-top; PR numbers, URLs or branch names
```

`gh stack link` pushes the branches, creates a PR for any branch that lacks one, corrects any base that does not match the chain, and creates or extends the Stack. It is **additive** — it never removes a PR from a stack — and it stores no local tracking state, so it composes with jj, Sapling, git-town, or plain git. `--base <branch>` sets the trunk for the bottom of the stack; `--open` marks the PRs ready for review.

**Whole stack up front.** If you are building the layers yourself and want the PRs opened together:

```bash
gh stack init feature-auth feature-api feature-ui   # adopts existing branches, creates missing ones
gh stack add api-routes                             # add a layer on top of the current stack
gh stack submit                                     # push every branch, open every PR, create the Stack
```

`gh stack submit` opens an editor to draft each PR's title and body; `--auto` skips it and uses generated titles (and creates the PRs as drafts unless you pass `--open`). Local stack metadata lives in `.git/gh-stack`, which is not committed.

**Verify the link landed** — do not assume it from the exit code:

```bash
gh stack view --short
gh pr view <pr> --json stack      # PullRequest.stack { id size baseRefName entries number }
```

Every PR in the stack must report the same stack id. `PullRequest.stackEntry { id position stack pullRequest }` gives one PR's position.

## Restacking after a lower layer merges

A merge queue squash-merges, so the parent's commits land on `main` with **new SHAs**. The old parent tip is no longer an ancestor of `main`, and a plain `git rebase origin/main` would replay the parent's commits on top of content `main` already has.

**First choice:**

```bash
gh stack sync
```

`sync` fetches, reconciles with the remote stack, fast-forwards trunk, cascade-rebases every branch onto its updated parent, pushes with `--force-with-lease`, re-syncs PR state, and re-links the stack's open PRs. For a branch whose parent PR has **merged**, it switches to `--onto` mode by itself — which is exactly this case. `--prune` also deletes local branches for merged PRs.

If `sync` reports a conflict it restores every branch untouched and hands you to the interactive form:

```bash
gh stack rebase              # cascading rebase, with --continue / --abort
gh stack rebase --downstack  # only the branches below the current one
gh stack rebase --upstack    # only the branches above it
```

**`gh stack sync` can exit 0 having done nothing.** On a **diverged** stack — you added a branch locally while different PRs were added to the stack on GitHub — a non-interactive terminal aborts the sync with a success exit and pushes nothing. Never read the exit code as the verdict:

```bash
gh pr diff <pr> --name-only      # must list ONLY that layer's files
```

If files that layer never touched are listed, the restack did not do what you intended. Stop rather than pushing.

## Fallback: the manual `--onto` recipe

Reach for this when:

- `gh stack` is not installed and installing it is not an option right now;
- the PRs were never linked, so `sync` has no stack to reconcile;
- `gh stack sync` aborted on a diverged stack;
- the parent was **rebased or amended mid-review**, where the cascade conflicts on the parent's own commits — `sync` is a rebase too, so it hits the same wall.

Cut at the old parent tip so only your own commits replay:

```bash
git fetch origin
# OLD_BASE = the parent branch's tip SHA from when you stacked
git rebase --onto origin/main <OLD_BASE_SHA> <your-branch>
gh pr edit <PR> --base main      # only if GitHub has not auto-retargeted already
git push --force-with-lease
```

Resolve any conflict against **`main`'s** version — the parent may have been reworked before merging, and your change has to re-home into its merged shape. Verify:

```bash
git rev-list --count HEAD..origin/main                              # 0 = not behind
git merge-tree $(git merge-base HEAD origin/main) HEAD origin/main  # no conflict hunks
gh pr diff <PR> --name-only                                         # only your files
```

Right after a base swap GitHub may briefly report the PR `DIRTY` while it recomputes — re-check; it settles to `MERGEABLE`/`BLOCKED`.

If the parent was rewritten so heavily that even `--onto` tangles, rebuild instead: `git checkout -B <your-branch> origin/main` then `git cherry-pick <your-own-commit>`.

## Merging a stack

```bash
gh stack merge            # interactive picker over the current stack
gh stack merge <pr>       # everything up to and including that PR
gh stack merge --yes      # non-interactive; merges the whole stack
```

Every PR up to your chosen one is merged in a single all-or-nothing operation: if one cannot merge, none do. Only basic PR state (open, not draft) is checked first — GitHub evaluates branch protection and repository rules when the merge runs and reports failures back. **Bypassing merge requirements is not supported**, deliberately.

**Under a merge queue, `merge` enqueues rather than merges.** The queue owns the strategy, so `--merge-method` / `--squash` / `--rebase` are ignored with a warning. The selected PRs are added to the queue together, but GitHub's own documentation says they "may land in separate groups rather than all at once" — and merge-queue support for stacks was still rolling out progressively as of the changelog.

### Enqueueing one layer, without `gh stack merge`

**`gh pr merge` refuses a linked stack member outright**, at any layer:

> This pull request is part of a stack and must be enqueued using the asynchronous merge REST API

So a wrapper that shells out to `gh pr merge` cannot enqueue a stack at all. The call that works is [`PUT /repos/{owner}/{repo}/pulls/{n}/merge-async`](https://docs.github.com/rest/pulls/pulls#merge-a-pull-request-asynchronously):

```bash
gh api -X PUT repos/<owner>/<repo>/pulls/<pr>/merge-async \
  -f merge_action=merge_queue -f sha=<head>
# -> {"status":"pending","details":{"message":"Merge request enqueued.",…}}
```

`merge_action=merge_queue` is what keeps this a **queue** operation — do not reach for `PUT .../pulls/{n}/merge` because the path looks similar; that one is a direct merge and bypasses the queue. HTTP 409 means GitHub already holds a merge request for the PR, which is the desired end state.

Same blast radius as `gh stack merge`: GitHub's docs say "all pull requests in the stack up to and including the requested PR will be merged into the base branch". Requesting the bottom enqueues only the bottom. Name the PR deliberately.

**Measured 2026-09-22 on one repo (`longeye-ai/monorepo`), one three-PR stack** — treat it as one data point, not as GitHub-wide behaviour, and re-run the reads on your own repo:

- **The queue took the whole stack as one group.** All three entries showed `mergeQueueEntry.state = AWAITING_CHECKS` simultaneously and landed as three merge commits 22 seconds apart. The upper layers were **not** retargeted to the trunk first — they merged out of the queue with their stacked bases intact, so no restack happened between layers. Until you have measured your own repo, keep treating the layers as landing independently: enqueue the bottom, let it land, restack, enqueue the next.
- **A linked stacked PR DID carry required checks.** `gh pr checks <child> --required` reported the full required set on both upper layers, and they were green before the merge. The historical observation below is the one this contradicts, and only for a *linked* stack.

**Still true for an UNLINKED stacked PR**, and not re-measured: required checks are configured on the trunk, so a PR based on a plain branch has none — `gh pr checks <pr> --required` returns nothing and the PR can look green while nothing gates it. A PR that merely targets another PR's branch is not a Stack, so run `gh stack link` before relying on the paragraph above.

## Rules that native stacks do not retire

- **Pass the base explicitly.** `gh pr create --base <parent-branch>`, always. An omitted base opens against the trunk with the parent's commits folded into your diff.
- **Three-dot diffs against the resolved base**, never a hardcoded `origin/main`: `git diff origin/<base>...HEAD`. Two dots renders upstream commits as deletions.
- **Never arm auto-merge on a stacked PR** — it merges into the *parent branch*, not the trunk. Arm it only once the base has retargeted to the trunk.
- **A parent closed WITHOUT merging strands the stack.** GitHub auto-retargets only on *merge*. Recover with the manual `--onto` recipe, then audit the file list before pushing — merging un-audited ships the parent's withdrawn commits.
- **Merging a child into its parent's branch moves the parent's head**, which dequeues the parent if it is in a merge queue. Sequence bottom-up.
- **Assert the branch before every commit** and audit `git diff --name-only <base>...HEAD` before every push. Driving a stack means many checkouts, and an edit lands on whichever branch you happen to be standing on.

## Navigation

```bash
gh stack view                 # full stack with PR links
gh stack checkout <n|pr|url|branch>   # pull down and switch to a stack
gh stack up / down / top / bottom / trunk / switch
gh stack modify               # TUI: drop, fold, insert, rename, reorder branches
gh stack unstack              # remove the stack on GitHub (--local: local tracking only)
```
