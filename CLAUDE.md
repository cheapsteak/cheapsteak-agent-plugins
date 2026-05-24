# cheapsteak-agent-plugins

Claude Code marketplace.

## Adding a plugin

1. `mkdir -p plugins/<name>/.claude-plugin plugins/<name>/skills`
2. Write `plugins/<name>/.claude-plugin/plugin.json` with `name`, `version`, `description`, `author`.
3. Add an entry to `.claude-plugin/marketplace.json` with `source: "./plugins/<name>"`.
4. Add a row to the table in `README.md`.
5. Add an entry to `CHANGELOG.md`.

## Adding a skill to a plugin

1. Create `plugins/<plugin>/skills/<skill>/SKILL.md`.
2. Frontmatter uses these fields only: `name`, `description`, `argument-hint`, `disable-model-invocation`, `user-invocable`, `compatibility`, `license`, `metadata`. **Do not** use `args` or `model_invocable`.
3. Bump the plugin's version (patch for a new skill, minor for breaking changes).

## Versioning

Bumping a plugin's version requires updating all three:

- `plugins/<plugin>/.claude-plugin/plugin.json`
- The plugin's entry in `.claude-plugin/marketplace.json`
- A new `CHANGELOG.md` entry at the top, format:

  ```markdown
  ## [plugin-name] [version]

  Brief description.

  **New:** ...
  **Changed:** ...
  **Fixed:** ...
  ```
