---
name: rebase
description: Rebase the current branch onto a target branch with safe conflict resolution. Use when the user says "rebase", "rebase on main", "update my branch", "pull in latest changes from main", "sync with main", or when resolving rebase conflicts. Handles stashing uncommitted changes, generated file conflicts, and cascading conflict recovery.
argument-hint: "[target] — branch to rebase onto; no args = origin/main, 'origin/branch' = remote, local name = local branch"
---

# Rebase Current Branch

## Argument Handling

- **No arguments**: fetch origin, rebase on `origin/main`
- **"origin/branch"** (e.g., `origin/develop`): fetch origin, rebase on that remote branch
- **Local branch name**: rebase on that local branch (no fetch)

## Steps

1. **Check for uncommitted changes**
   - Run `git status --porcelain`
   - If there are changes, run `git stash push -m "rebase-temp-$(date +%s)"`
   - Remember to pop the stash after rebase completes

2. **Parse arguments and determine target**
   - No args → fetch origin, target is `origin/main`
   - Contains "/" (e.g., `origin/develop`) → split into remote and branch, fetch remote, target is `remote/branch`
   - Anything else → target is that local branch name, no fetch

3. **Fetch if needed**: `git fetch <remote>`

4. **Start rebase**: `git rebase <target>`

5. **Handle conflicts carefully** (see below)

6. **Continue until rebase is complete**

7. **Restore stashed changes** if step 1 stashed anything: `git stash pop`

## Handling Conflicts

**CRITICAL: Investigate before resolving.**

### Understanding "ours" vs "theirs" During Rebase

**WARNING:** During a rebase, the meanings of "ours" and "theirs" are counterintuitive:

- `--ours` = the branch we're rebasing **onto** (e.g., `origin/main`) — this is HEAD during the rebase
- `--theirs` = **our commits** being replayed (the feature branch)

This is the opposite of what you might expect! When rebasing onto main, "ours" is main and "theirs" is your feature branch.

### Generated Files — Always Take Main's Version and Re-run Generation

**For conflicts in generated files, NEVER manually resolve.** Instead, take the version from the branch you're rebasing onto (main) and then re-run the generation command.

Identify generated files by looking for patterns like:
- Files in `generated/` or `__generated__/` directories
- Lock files (`package-lock.json`, `pnpm-lock.yaml`, `poetry.lock`, etc.)
- Schema dumps, codegen output, compiled artifacts

**When you encounter a generated file conflict, ask the user:**

> I found a conflict in generated file(s): `<list files>`
>
> How would you like to handle regeneration?
>
> 1. **Regenerate at end** (recommended) — Faster, regenerate once after rebase completes
> 2. **Regenerate at each step** — Slower, but each commit stays internally consistent
>
> Trade-offs:
> | Approach | Pros | Cons |
> |----------|------|------|
> | At end | Faster; avoids cascading conflicts | Intermediate commits may have inconsistent generated files |
> | At each step | Clean history; each commit is valid | Slower; risk of cascading conflicts |

**Option 1: Regenerate at end**

1. Accept the target branch's version (regeneration will overwrite it):
   ```bash
   git checkout --ours <generated-file>
   ```

2. Stage and continue:
   ```bash
   git add <generated-file>
   git rebase --continue
   ```

3. Repeat for any additional conflicts until rebase completes.

4. After rebase completes, re-run the relevant generation commands. Ask the user what commands to run if you don't know.

5. Commit the regenerated files:
   ```bash
   git add <generated-files>
   git commit -m "Regenerate generated files after rebase"
   ```

**Option 2: Regenerate at each step**

1. Accept the target branch's version:
   ```bash
   git checkout --ours <generated-file>
   ```

2. Re-run the relevant generation commands now.

3. Stage and continue:
   ```bash
   git add <regenerated-files>
   git rebase --continue
   ```

4. Repeat for each subsequent conflict.

### Regular (Non-Generated) Files

For each conflicting file:

1. **Understand target branch changes first**
   ```bash
   git log -p -n 3 <target> -- <conflicting-file>
   ```
   This shows recent changes to understand WHY the target branch modified this file.

2. **Check our branch's intent**
   ```bash
   git log -p -n 3 HEAD -- <conflicting-file>
   ```

3. **Resolve with both intents in mind**
   - The goal is to preserve BOTH the target branch's changes AND our branch's changes
   - If the target branch refactored code structure, adapt our changes to work within the new structure
   - Don't blindly pick "ours" or "theirs"

4. **Stage and continue**
   ```bash
   git add <resolved-file>
   git rebase --continue
   ```

5. **If a conflict is too complex or unclear**, describe the situation and ask for guidance before proceeding

### Cascading Conflicts — Offer to Squash and Retry

**If you encounter repeated conflicts across multiple commits** (e.g., resolving the same file in commit after commit, or conflicts that compound on each other), ask the user:

> I'm seeing cascading conflicts across multiple commits. This can happen when:
> - The same files were modified in multiple commits on your branch
> - Main has diverged significantly from your branch
> - Earlier conflict resolutions are causing new conflicts in later commits
>
> Would you like to **squash your commits first** and retry the rebase? This reduces the rebase to a single conflict resolution instead of one per commit.
>
> Trade-offs:
> | Approach | Pros | Cons |
> |----------|------|------|
> | Continue commit-by-commit | Preserves individual commit history | More conflicts to resolve; risk of compounding errors |
> | Squash and retry | Only one conflict resolution; cleaner process | Loses granular commit history (can be re-split later if needed) |

**If user chooses to squash and retry:**

1. Abort the current rebase:
   ```bash
   git rebase --abort
   ```

2. Count commits on the branch since it diverged from main:
   ```bash
   git rev-list --count origin/main..HEAD
   ```

3. Squash all commits into one (replace N with the count from step 2):
   ```bash
   git reset --soft HEAD~N
   git commit -m "Squashed: <brief description of all changes>"
   ```

4. Now retry the rebase:
   ```bash
   git fetch origin
   git rebase origin/main
   ```

5. Resolve the single conflict (all your changes vs all of main's changes).

6. If the user wants to restore granular history later, they can use `git rebase -i` to split the squashed commit after the rebase succeeds.

## After Completion

- Verify the rebase succeeded: `git log --oneline -5`
- If you stashed changes, verify they were restored: `git stash list`
