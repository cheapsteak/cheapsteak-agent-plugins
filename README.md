# cheapsteak-agent-plugins

Chang's Claude Code plugins — generic dev workflow, skill authoring, and macOS/web utilities.

## Installation

```bash
# Add the marketplace
/plugin marketplace add https://github.com/cheapsteak/cheapsteak-agent-plugins.git

# Install individual plugins
/plugin install git-flow@cheapsteak-agent-plugins
/plugin install skill-authoring-kit@cheapsteak-agent-plugins
/plugin install agent-workflow@cheapsteak-agent-plugins
/plugin install macos-ops@cheapsteak-agent-plugins
/plugin install web-tools@cheapsteak-agent-plugins
/plugin install gql@cheapsteak-agent-plugins
```

Restart Claude Code after installation — plugins added mid-session don't load.

## Plugins

| Plugin | Version | Description |
|--------|---------|-------------|
| **`git-flow`** | 0.2.0 | Commit, push, PR, rebase, review-feedback workflows on top of `git` + `gh` |
| **`skill-authoring-kit`** | 0.1.0 | Build Claude skills, plugins, and hooks |
| **`agent-workflow`** | 0.2.0 | Adversarial review, scheduled wake-ups, background-monitor polling, `/explain` command |
| **`macos-ops`** | 0.1.0 | macOS sysadmin (memory diagnosis today) |
| **`web-tools`** | 0.1.0 | Playwright-CLI-based browsing |
| **`gql`** | 0.1.0 | GraphQL / Apollo patterns |

### Skill → plugin mapping

| Plugin | Skills |
|--------|--------|
| `git-flow` | `pr`, `rebase`, `monitor-pr`, `address-pr-feedback` |
| `skill-authoring-kit` | `skill-authoring`, `create-plugin`, `claude-hooks` |
| `agent-workflow` | `adversarial-review`, `later`, `monitor` |
| `macos-ops` | `diagnose-memory` |
| `web-tools` | `browse` |
| `gql` | `apollo-optimistic-updates` |

## Repository layout

```
cheapsteak-agent-plugins/
├── .claude-plugin/
│   └── marketplace.json
├── plugins/
│   └── <plugin-name>/
│       ├── .claude-plugin/
│       │   └── plugin.json
│       ├── skills/
│       │   └── <skill-name>/
│       │       └── SKILL.md
│       └── README.md
├── CHANGELOG.md
├── CLAUDE.md
└── README.md
```

## Versioning

When bumping a plugin's version, update **all three**:

1. `plugins/<plugin>/.claude-plugin/plugin.json`
2. The matching entry in `.claude-plugin/marketplace.json`
3. A new entry at the top of `CHANGELOG.md`

## Codex support

Deferred. Anthropic's plugin format works for Claude Code; for Codex we'd add an equivalent manifest per plugin once the format is settled.

## License

MIT.
