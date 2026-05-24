# skill-authoring-kit

Meta-skills for building things that extend Claude Code itself.

## Skills

- **skill-authoring** — Anthropic's official skill-authoring guide, distilled. Covers file structure, frontmatter, progressive disclosure, and debugging skills that won't trigger. Bundles the full Anthropic guide as a reference.
- **create-plugin** — End-to-end plugin scaffolding: directory structure, plugin.json, SKILL.md, marketplace registration, and `enabledPlugins` setup. Includes the three-way name-consistency rule that's easy to get wrong.
- **claude-hooks** — Writing PostToolUse/PreToolUse hooks correctly. Covers the only output shape that surfaces messages to Claude (the `hookSpecificOutput` envelope), the auto-fix anti-pattern, transcript reading, and jq patterns.

## Requirements

- `jq` (for `claude-hooks` transcript examples)
