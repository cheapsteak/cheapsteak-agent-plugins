---
name: create-plugin
description: Create a new Claude Code plugin for any marketplace (local directory, GitHub, or custom). Handles plugin.json, SKILL.md, marketplace registration, and settings enablement. Use when the user says "create a plugin", "add a plugin", "new plugin", "make this a plugin", or wants to package a skill for distribution.
---

# Create Plugin

Create a new Claude Code plugin for distribution via a marketplace. Handles the full
lifecycle: directory structure, metadata, skill content, marketplace registration, and
settings enablement.

## Plugin Structure

Every plugin follows this structure:

```
{plugin-name}/
├── .claude-plugin/
│   └── plugin.json           # Plugin metadata (required)
├── skills/
│   └── {skill-name}/
│       └── SKILL.md          # Skill instructions (required)
├── commands/                  # Optional slash commands
├── hooks.json                 # Optional hooks
├── scripts/                   # Optional executable code
└── references/                # Optional docs loaded on demand
```

A plugin can contain multiple skills, commands, and hooks. Most plugins contain one skill.

## Process

### Step 1: Determine target marketplace

Ask if not clear from context:
- Which marketplace? (a local directory, a GitHub repo, or a new one to create)
- What's its path / URL and its registered name?

Check existing marketplaces:
```bash
grep -A4 "extraKnownMarketplaces" ~/.claude/settings.json
```

### Step 2: Determine plugin contents

- **Name**: kebab-case, must match directory name and all metadata references
- **Purpose**: what the plugin does (1-2 sentences)
- **Triggers**: what phrases or commands activate it
- **Type**: standalone skill, tool integration, hook bundle, etc.
- **Skills**: usually one, can be multiple

### Step 3: Create the directory

```bash
mkdir -p {marketplace-path}/plugins/{plugin-name}/.claude-plugin
mkdir -p {marketplace-path}/plugins/{plugin-name}/skills/{plugin-name}
```

### Step 4: Write plugin.json

Create `{plugin-name}/.claude-plugin/plugin.json`:

```json
{
  "name": "{plugin-name}",
  "version": "1.0.0",
  "description": "{Brief description}"
}
```

CRITICAL: The `name` field must exactly match the directory name.

### Step 5: Write SKILL.md

Create `{plugin-name}/skills/{plugin-name}/SKILL.md` following the skill-authoring
guide. If the `skill-authoring` skill from this plugin is installed, consult it for
the full guide; otherwise it's also available at the source of this plugin.

Key requirements:
- YAML frontmatter with `name` (kebab-case, matches folder) and `description`
  (includes both what it does AND trigger conditions)
- Description under 1024 characters, no XML angle brackets
- Imperative/infinitive writing style (verb-first instructions)
- Keep under 5,000 words — move detailed docs to `references/`

### Step 6: Register in marketplace

Add the plugin to the marketplace's catalog file (usually `.claude-plugin/marketplace.json`):

```json
{
  "name": "{plugin-name}",
  "source": "./plugins/{plugin-name}",
  "description": "{Brief description}",
  "keywords": ["{keyword1}", "{keyword2}"]
}
```

### Step 7: Enable in settings

Add to `enabledPlugins` in `~/.claude/settings.json`:

```json
"{plugin-name}@{marketplace-name}": true
```

CRITICAL: The `@{marketplace-name}` suffix must match:
- The key in `extraKnownMarketplaces` in settings.json
- The `name` field in the marketplace's `.claude-plugin/marketplace.json`

Mismatches cause "Plugin not found in marketplace" errors.

### Step 8: Commit and verify

Commit all new files to the marketplace repo. Tell the user to restart their
Claude Code session — plugins added mid-session won't load.

## Verification Checklist

Before finishing, verify:
- [ ] `{name}/.claude-plugin/plugin.json` exists with correct `name`
- [ ] `{name}/skills/{name}/SKILL.md` exists with valid frontmatter
- [ ] Entry added to marketplace catalog with `source` pointing to plugin directory
- [ ] `{name}@{marketplace}` added to `enabledPlugins` in settings.json
- [ ] Plugin name is consistent across all locations
- [ ] Committed and pushed (if the marketplace is a git repo)
