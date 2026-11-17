# Acquisition, live experiments and close-out

## Phase 1: acquire, least invasive first

Try these in order. Stop at the first that answers the question.
1. Public docs, changelogs, public static assets: JS chunks are often served without auth, so crawl from the page's script tags.
2. Packages, source repos, or the vendor's own instructions to AI agents.
3. Installed client binaries.
   - Copy the binary out.
   - Extract the embedded JS (e.g. a Bun or Electron bundle).
   - Run it only with `--version`.
4. User-performed captures: the user does the action and exports a HAR. Use this for flows the agent can't drive.
5. Authenticated sessions, only in an isolated browser profile (see below).

For each source, record:
- version id and hash;
- fetch date;
- every failed path, so later claims carry the right tag;
- a **boundary list**: what these sources can't answer.

## HAR and log redaction

Redact auth and proxy headers, cookies, bearer tokens, JWTs, API keys, `*token*`/`*secret*`/`*session*` fields and query parameters, and long opaque strings.

1. Copy the HAR into a new empty directory.
2. A `python3 -I` script that lives in another directory lists only the *names* of sensitive fields.
3. Write a redacted copy and work only from it.
4. Delete your unredacted copy. Never modify the user's original.
5. Tell the user whether their "sanitised" export still holds live tokens (response bodies often do), and to delete it.

Pipe every proxy or CLI log through the redactor before it reaches a file. Scope any proxy CA to one process (`NODE_EXTRA_CA_CERTS`), never the system store.

## Live experiments

**Template**, one per experiment:
- id;
- hypothesis;
- **prediction derived from the notes, written before running**;
- action;
- wire-level signature;
- observation;
- verdict (confirm or refute);
- confidence;
- raw file.

Upgrade tags from `[I]` to `[O]` only on observation.

**Discriminating designs that worked:**
- Hold one request at a local proxy (mitmdump) for 30 s while another writer changes the target. This shows whether the server enforces preconditions.
- Fingerprints a suspected storage engine must show (e.g. CRDT clocks on formatting, ids on moves).
- Two writers with controlled timing (keystroke → wait N s → other writer), predicted per scenario. Number the scenarios so evidence can be matched up later.
- A subagent whose only job is to make one specific tool call. This reproduces a bug caused by shared process state.

**Before planning on a nested or headless agent CLI**, probe its tool list for that version. Tools differ between interactive and `-p` modes.

**Ranking:** propose experiments in order of how much the result would change a decision. Drop edge cases when the user says so.

## Browser automation

- Use a separate Chrome:
  `--user-data-dir=<project-or-scratch>/pw-profile --remote-debugging-port=<p> --remote-debugging-address=127.0.0.1`.
  By default the user signs in by hand. Importing cookies from the user's own browser exposes every site's session, not just the one under test, and leaves secret files to clean up. Import only if the user asks, and only for the one site.
- Drive it with Playwright over CDP: page-level input, `page.on('request')` logging that is deny-by-default and records only allowed fields.
- Do a dry run on a harmless target first. No modifier shortcuts. Check each action landed.
- **Never** use OS-level input (computer-use, accessibility drivers) on the user's own browser: keystrokes land in whatever window is in front.
- Afterwards, kill that Chrome and delete the profile.

## Test objects

- **Name:** `zz-<study>-<purpose>`.
- **Ledger row at creation** (`experiments/LEDGER.md`): name, URL or id, creator agent, purpose, status.
- Subagents never delete.

## Close-out (Phase 11)

Checklist:
- [ ] every ledger row deleted or kept on purpose (deletes often need the user);
- [ ] captured secrets (HARs) deleted, and the user told to delete their own copies;
- [ ] isolated browser profiles deleted;
- [ ] background processes and dev servers stopped, without killing the user's own processes;
- [ ] scratch evidence copied into the project;
- [ ] final open-questions list written.
