---
name: skill-authoring
description: Anthropic's official guide to building Claude skills. Use when creating a new skill, editing an existing skill, reviewing skill structure, or debugging why a skill won't trigger.
---

# Skill Authoring Guide

Distilled from Anthropic's official guide. Full reference: `references/anthropic-skills-guide.md`

## File Structure

For full details on folder layout, naming rules, what goes where, and progressive disclosure levels, see `references/file-organization.md`.

```
skill-name/
├── SKILL.md              # Required — instructions with YAML frontmatter
├── scripts/              # Optional — executable code
├── references/           # Optional — docs loaded on demand
└── assets/               # Optional — templates, fonts, icons
```

**SKILL.md must be exactly that name** — case-sensitive, no variations.

**Folder name:** kebab-case only. No spaces, underscores, or capitals.

## Frontmatter

```yaml
---
name: skill-name
description: What it does. When to use it.
---
```

### name (required)
- kebab-case, no spaces or capitals
- Must match folder name
- Cannot contain "claude" or "anthropic" (reserved)

### description (required)
- Must include BOTH what the skill does AND when to use it (trigger conditions)
- Under 1024 characters
- No XML angle brackets (`<` or `>`)
- Include specific phrases users would say
- Mention relevant file types if applicable

**Good:**
```
Analyzes Figma design files and generates developer handoff documentation.
Use when user uploads .fig files, asks for "design specs", "component
documentation", or "design-to-code handoff".
```

**Bad:**
```
Helps with projects.
```

### Optional fields
- `license`: MIT, Apache-2.0, etc.
- `compatibility`: Environment requirements (1-500 chars)
- `metadata`: Custom key-value pairs (author, version, mcp-server)

## Progressive Disclosure (3 levels)

1. **Frontmatter** — always loaded in system prompt. Just enough for Claude to know when to use the skill.
2. **SKILL.md body** — loaded when Claude thinks the skill is relevant. Full instructions.
3. **Linked files** (`references/`, `scripts/`) — loaded only when needed during execution.

Keep SKILL.md under 5,000 words. Move detailed docs to `references/`.

## Writing Instructions

- Be specific and actionable — include exact commands, tool names, parameter names
- Use numbered steps with validation at each stage
- Include error handling for common failures
- Provide examples of typical usage
- Put critical instructions at the top, not buried
- Reference bundled resources clearly: `consult references/api-patterns.md for...`

## Debugging

**Skill doesn't trigger:** Description is too vague or missing trigger phrases. Test by asking Claude: "When would you use the [skill] skill?"

**Triggers too often:** Add negative triggers ("Do NOT use for simple data exploration") or narrow the scope.

**Instructions not followed:** Instructions may be too verbose, buried, or ambiguous. Put critical rules first. Use `CRITICAL:` prefix for must-follow rules. Consider bundling validation as a script instead of relying on language instructions.

**Large context issues:** Keep SKILL.md concise, move detail to references, limit enabled skills to avoid overload.
