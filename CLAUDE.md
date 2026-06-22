# cheapsteak-agent-plugins

Claude Code marketplace.

## Adding a plugin

1. `mkdir -p plugins/<name>/.claude-plugin plugins/<name>/skills`
2. Write `plugins/<name>/.claude-plugin/plugin.json` with `name`, `description`, `author`. **No `version` field** — see [Versioning](#versioning).
3. Add an entry to `.claude-plugin/marketplace.json` with `source: "./plugins/<name>"` (no `version` field).
4. Add a row to the table in `README.md`.
5. Add an entry to `CHANGELOG.md`.

## Adding a skill to a plugin

1. Create `plugins/<plugin>/skills/<skill>/SKILL.md`.
2. Frontmatter uses these fields only: `name`, `description`, `argument-hint`, `disable-model-invocation`, `user-invocable`, `compatibility`, `license`, `metadata`. **Do not** use `args` or `model_invocable`.
3. Just commit — no version bump needed (see [Versioning](#versioning)). Add a `CHANGELOG.md` entry.

## Versioning

**Plugins are intentionally unversioned.** Do not add a `version` field to any
plugin's `plugin.json` or to its entry in `.claude-plugin/marketplace.json`.

Why: Claude Code names each plugin's cache folder after its `version`. When a
version is bumped, CC fetches the new `<version>/` folder and sweeps the old one,
but it does **not** rewrite the user's `installed_plugins.json` pin ([bug
#52218](https://github.com/anthropics/claude-code/issues/52218)) — so the pin
dangles at the now-deleted folder and the plugin fails to load with
`Plugin "<name>" not cached at .../<name>/<old-version>`. Omitting `version` makes
CC key the cache on the git commit SHA instead (the model the official Anthropic
plugins use), so every push ships to users automatically and the cache never
drifts.

> "If you're iterating quickly, you should leave version unset so the git commit
> SHA is used instead." — [Plugins reference](https://code.claude.com/docs/en/plugins-reference.md)

The marketplace-level `version` in `.claude-plugin/marketplace.json` is fine to
keep — it labels the catalog, not a plugin cache folder.

Record changes in `CHANGELOG.md` using the commit date as the label:

```markdown
## [plugin-name] YYYY-MM-DD

Brief description.

**New:** ...
**Changed:** ...
**Fixed:** ...
```
