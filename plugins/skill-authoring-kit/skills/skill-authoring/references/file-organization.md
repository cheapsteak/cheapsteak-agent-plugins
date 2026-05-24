# Skill File Organization

## Required structure

```
skill-name/
├── SKILL.md              # Required — the skill itself
├── scripts/              # Optional — executable code
│   ├── process_data.py
│   └── validate.sh
├── references/           # Optional — docs loaded on demand
│   ├── api-guide.md
│   └── examples/
└── assets/               # Optional — templates, fonts, icons
    └── report-template.md
```

## Naming rules

| Thing       | Rule                          | Example              |
|-------------|-------------------------------|----------------------|
| Folder name | kebab-case only               | `notion-project-setup` |
| SKILL.md    | Exact case, no variations     | `SKILL.md` not `skill.md` |
| Skill name  | kebab-case, matches folder    | `name: notion-project-setup` |

Forbidden in names: spaces, underscores, capitals, "claude", "anthropic".

No `README.md` inside the skill folder — all docs go in `SKILL.md` or `references/`. (Use a repo-level README for human visitors when distributing via GitHub.)

## What goes where

### SKILL.md — the brain

Everything Claude needs to execute the skill. Two parts:

1. **YAML frontmatter** (always loaded) — `name`, `description`, and optional fields. This is how Claude decides whether to load the skill. Keep it tight.
2. **Markdown body** (loaded on activation) — step-by-step instructions, examples, error handling.

Keep under 5,000 words. If it's getting long, move detail to `references/`.

### scripts/ — deterministic logic

Executable code that the skill invokes via Bash. Use scripts when:
- Validation must be deterministic (not language-interpreted)
- You need data processing, API calls, or file manipulation
- A conditional check should no-op silently in some environments

Reference from SKILL.md with exact paths:
```markdown
Run `python scripts/validate.py --input {filename}` to check data format.
```

Scripts can't use `$SKILL_PATH` — there's no such env var. Either:
- Reference scripts by relative path from the working directory
- Place scripts alongside SKILL.md and document the expected location
- Inline short logic directly in Bash commands

### references/ — deep knowledge

Detailed docs that Claude reads only when needed (progressive disclosure level 3). Good for:
- API pattern guides
- Schema documentation
- Extended examples
- Domain-specific reference material

Link from SKILL.md:
```markdown
Before writing queries, consult `references/api-patterns.md` for rate limiting and pagination patterns.
```

### assets/ — static resources

Templates, fonts, icons, or other files the skill uses in its output. Not instructions — just materials.

## Progressive disclosure

The three levels control when content enters Claude's context:

| Level | What                | When loaded               | Goal                        |
|-------|---------------------|---------------------------|-----------------------------|
| 1     | YAML frontmatter    | Always (system prompt)    | Should I use this skill?    |
| 2     | SKILL.md body       | When skill seems relevant | How do I execute this?      |
| 3     | references/, scripts/ | When explicitly needed   | Deep detail for edge cases  |

This matters because context is finite. Front-load the decision-making info, defer the details.
