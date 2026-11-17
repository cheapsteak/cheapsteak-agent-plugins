---
name: migrate-mac
description: Move a developer Mac to a new one with Migration Assistant. Covers what to delete first so the copy is small (dependency folders, package stores, build output, sparse VM disk images), what recreates those folders while you delete them, and what to fix on the new Mac (Nix reinstall, Okta Verify, Xcode first launch, toolchains, broken links). Use when the user is about to migrate or has just migrated a Mac, says "Migration Assistant", "moving to a new MacBook" or "clean up before migrating", or finds Nix or direnv tools missing on a Mac set up from another one.
---

# Migrate a developer Mac

Migration Assistant copies the whole Data volume and can't skip folders, so anything you don't
want on the new Mac has to be deleted before you start. On a developer Mac most of it
regenerates. On one Mac, deleting it took used space from about 390 GiB to 225 GiB and the file
count from 26.1 million to 5.1 million; `node_modules` and `.venv` folders alone were 78 GiB.
Copy and delete time follow the file count more than the bytes.

## Rules

- **Delete only what regenerates.** Never delete a checkout or worktree itself, a database data
  directory, or anything that may hold the only copy of someone's work. Drop databases with SQL
  or the project's own tooling, never by deleting files.
- **Show the plan first.** List each category with its paths, size and how it comes back, and get
  the user's OK before deleting.
- **Skip anything in use** (step 1) **and anything git tracks** (step 2).
- **Measure with `df -h /System/Volumes/Data`** before and after each category. `du` counts every
  APFS clone at full size, so it overstates what a deletion frees.
- **Keep a restore checklist on the Desktop**, e.g. `~/Desktop/after-migration/AFTER-MIGRATION.md`.
  It moves with the user. Record each deletion, how it comes back, and everything you stopped.

## Before the move

### 1. Stop what recreates folders while you delete them

A `.venv` or `node_modules` deleted while something still uses it can come back within minutes:

- **direnv.** A project whose `.envrc` installs missing dependencies reinstalls them as soon as a
  shell enters the checkout. Close terminals and agent sessions whose working directory is in
  such a checkout.
- **Editors.** VS Code's Ruff extension runs `ruff server` from the project's `.venv` and restarts
  it if it is killed. Close the window instead.
- **LaunchAgents that run from a project's virtualenv.** Stop each one with
  `launchctl bootout gui/$(id -u)/<label>`. It loads again at login on the new Mac, and works
  once its venv is reinstalled.
- **Dev servers, file watchers and agent sessions** running from a folder you are about to delete.

Check a path before deleting it: `lsof -nP | grep -F <path>` and
`ps -axo pid,command | grep -F <path>`.

### 2. Inventory what regenerates, biggest first

- **Dependency folders.** `node_modules` and virtualenvs in every checkout and worktree. A uv venv
  has a `uv =` line in its `pyvenv.cfg`. They come back with the project's install command, or by
  themselves through direnv.
- **Package stores and caches.** Prefer each tool's own command: `uv cache clean`,
  `pnpm store prune`, `npm cache clean --force`, `brew cleanup --prune=all`. Then
  `~/Library/Caches` (skip `com.apple.*`), `~/.cache` and `~/.bun/install/cache`.
- **Build output.** `.build`, Rust `target` (it contains `CACHEDIR.TAG`), `.terraform`, `.gradle`,
  `.pytest_cache`, `.mypy_cache`. **Skip any folder git tracks:** some repos commit a
  `.gitignore` inside a build folder, and a blanket sweep then deletes a tracked file in every
  worktree. `git -C <repo> ls-files -- <dir>` prints nothing when git tracks nothing inside it.
- **Sparse VM and container disk images.** They are large on paper and small on disk, and nothing
  promises they copy small (see "Not confirmed"). OrbStack's
  `~/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data/data.img.raw` was 460 GiB apparent and
  2.3 GiB real. Docker Desktop's is `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`;
  colima and lima keep theirs under `~/.colima` and `~/.lima`. Compare `ls -lh` (apparent) with
  `du -h` (real). Delete with the engine stopped. Images come back with the next pull, but data in
  volumes is lost, so ask first.
- **Large downloads that come back by themselves:**
  - Claude desktop's VM image, `~/Library/Application Support/Claude/vm_bundles` (9.3 GiB); quit
    Claude first.
  - Chrome's on-device model, `~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel`
    (4.0 GiB); quit Chrome first.
- **Server logs.** Postgres.app's `~/Library/Application Support/Postgres/var-<version>/postgresql.log`
  had grown to 4.7 GiB. Empty it with that server stopped.
- **Old toolchain versions.** Volta's non-default Node versions under `~/.volta/tools/image/node/`,
  old Claude Code builds under `~/.local/share/claude/versions/` (keep the running one), and old
  Homebrew versions.
- **Everything else over 1 GiB.** `find ~ -xdev -type f -size +1G -exec ls -lh {} + 2>/dev/null`
  takes minutes. Run it in the background with output appended to a file: a time limit that kills
  `find` loses whatever it had buffered.

### 3. Delete

- **Expect about 27,000 files a second.** That was the rate with four parallel `rm -rf` processes
  on one Mac, each using about half a core. The bottleneck was `fseventsd`, the service that
  records file changes for apps watching the disk, at 175% CPU. More parallel deletions mostly add
  to its load. Quitting apps that watch those folders (editors, sync clients, worktree managers)
  helps a little.
- **Delete from a NUL-separated list,** e.g. `xargs -0 -P4 -n1 rm -rf -- < list`.
- **Record the `df` change per category** in the checklist.

### 4. Check what will fail on the other side

- **LaunchAgents whose program is gone** fail on every run, before and after the move:

  ```sh
  for p in ~/Library/LaunchAgents/*.plist; do
    i=0
    while arg=$(plutil -extract "ProgramArguments.$i" raw -o - "$p" 2>/dev/null); do
      case $arg in /*) [ -e "$arg" ] || echo "$(basename "$p" .plist): missing $arg";; esac
      i=$((i+1))
    done
  done
  ```

  An agent installed from a worktree breaks when that worktree is removed. Remove it, or install
  it again from a stable path.
- **Save what to reinstall:** `brew bundle dump --file ~/Desktop/after-migration/Brewfile` and
  `ls /Applications > ~/Desktop/after-migration/applications.txt`.

## After the move

**Comes across intact:** apps, Homebrew in `/opt/homebrew`, Volta and rustup toolchains, home-folder
config, LaunchAgents and LaunchDaemons, Postgres.app data, and everything in `/etc`.

### Nix has to be reinstalled

Migration Assistant copies the Data volume only, and Nix keeps its store on its own APFS volume
(`Nix Store`, mounted at `/nix`). So `/nix` arrives empty. `diskutil info "Nix Store"` tells you
for sure: on a migrated Mac it finds no such volume. Everything about Nix that lives in `/etc` and
the home folder may come across:
- an `/etc/fstab` line naming the old Mac's volume UUID;
- `nix` in `/etc/synthetic.conf`;
- the `org.nixos.nix-daemon` and `org.nixos.darwin-store` LaunchDaemons;
- the `nixbld` group and its `_nixbld` users;
- `/etc/nix/`, the Nix block in `/etc/bashrc`, and the `/etc/*.backup-before-nix` files;
- `~/.nix-profile` and `~/.nix-defexpr`.

None of it may be there either; then it is a plain fresh install.

1. **Clear stale `*.backup-before-nix` files.** The installer aborts when `<file>.backup-before-nix`
   exists and differs from `<file>`; an identical backup can stay. Check each one with `diff`. If
   the live file differs only by the `# Nix` … `# End Nix` block, moving the backup back over it is
   the same as stripping the block. A backup that itself contains a Nix block means Nix was
   installed twice; the live file then has the block twice.
2. **Run the installer from Terminal.app, after granting Terminal Full Disk Access** (System
   Settings → Privacy & Security). Without it, it creates the volume and build users and then dies
   at `chown: /nix/.Trashes: Operation not permitted`. Running it again from Terminal.app is safe.
3. **Install:** `sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon`.
   It offers to replace the old Mac's `fstab` line, `synthetic.conf` entry and `darwin-store`
   daemon; answer yes (`--yes` does). It keeps the `_nixbld` users when their ids match its
   defaults (GID 350, UIDs from 351).
4. **Put back your `/etc/nix/nix.conf` additions.** The installer rewrites that file in full (as of
   2.35.6), so a line you added, such as `!include nix.custom.conf`, is gone. It leaves other files
   in `/etc/nix` alone. `~/.config/nix/nix.conf` comes across untouched.
5. **Open new terminals and restart agent sessions** that started before Nix existed. direnv
   restores the PATH the session started with, which has no Nix in it.
6. **Expect the first `direnv allow` in each flake project to build cold** and download a lot.

### Everything else

- **Okta Verify has to be enrolled again.** Its keys are tied to the old Mac's Secure Enclave and
  can't be exported, while the app and its settings move. The empty app keeps answering Okta's
  probe, so sign-in opens "Open Okta Verify" windows without end. Quit Okta Verify, sign in with
  your password, then enroll again.
- **Xcode:** `xcodebuild -checkFirstLaunchStatus` exits non-zero (69 on one Mac) until you run
  `sudo xcodebuild -license accept` and `sudo xcodebuild -runFirstLaunch`.
- **Broken links to deleted build output.** A tool linked from `~/.local/bin` into a project's
  `target/release` needs a rebuild. Find them with
  `find ~/.local/bin /usr/local/bin -type l ! -exec test -e {} \; -print`.
- **rustup's default `stable` is whatever was installed last** (1.88 on one Mac in late 2026). A
  project that needs a newer Rust can build without changing the default:
  `rustup toolchain install <version>`, then `cargo +<version> build`.
- **`brew bundle check` says "needs to be installed or updated" for packages that are only
  outdated.** `brew list --versions <name>` tells the two apart.
- **Dependencies** come back per checkout the first time its install command or direnv runs.
- **Docker engines start empty.** Pull images again.
- **Database servers:** check they are running. Postgres.app's servers did not start when the
  app was opened in the background with `open -g`; `pg_ctl -D <data dir> -o "-p <port>" -w start`
  started them.

## Not confirmed

Whether Migration Assistant keeps APFS clones and sparse files compact. Copied to another
volume, a clone "assumes full size" and sparse files "are prone to explode to full size"
([Eclectic Light](https://eclecticlight.co/2024/10/08/apfs-incompatibilities-and-how-to-live-with-them/)),
but that article does not cover Migration Assistant, and Apple does not document what it does. One
move that deleted the big sparse image and most clones first went from 224.8 GiB used on the old
Mac to 203.5 GiB on the new one, which neither confirms nor rules out expansion. Until someone
measures it, delete sparse disk images before moving.
