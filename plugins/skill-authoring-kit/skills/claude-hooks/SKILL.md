---
name: claude-hooks
description: Guide for writing Claude Code hooks. Use when creating or modifying PostToolUse/PreToolUse hooks, making hooks emit warnings to Claude, or debugging why hook output isn't visible.
---

# Claude Code Hooks

## Hook output visibility

Only one pattern reliably surfaces messages back to Claude from a PostToolUse hook — JSON to stdout with `hookSpecificOutput`:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "your message here"
  },
  "continue": true
}
```

**These do NOT work for showing messages to Claude:**
- `echo "..." >&2` (stderr) — only visible to the user in verbose mode
- `echo "..."` (plain stdout) — not shown to Claude
- `{ "additionalContext": "..." }` (bare, without `hookSpecificOutput`) — not shown to Claude

## Shell helper for emitting warnings

```bash
emit_warning() {
  local msg="$1"
  local escaped
  escaped=$(printf '%s' "$msg" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "$escaped"
  },
  "continue": true
}
EOF
}
```

## Do not auto-fix files

Hooks must not auto-format or rewrite files (e.g. `prettier --write`, `ruff format`, `pg_format --inplace`).

**Why:** Auto-fixing rewrites the file after Claude's edit. Claude's next edit command uses the file content it last read — if the file changed underneath it, the `old_string` won't match and the edit fails.

Instead, run formatters in check mode and emit a warning with the fix command:

```bash
# prettier
prettier_output=$(npx prettier --check "$file_path" 2>&1)
if [ $? -ne 0 ]; then
  emit_warning "Prettier found formatting issues in $file_path. Fix with: npx prettier --write $file_path"
fi

# ruff
ruff_output=$(ruff format --check "$file_path" 2>&1)
if [ $? -ne 0 ]; then
  emit_warning "ruff format check failed for $file_path. Fix with: ruff format $file_path"
fi

# pg_format (no --check flag — diff manually)
formatted=$(pg_format --spaces 2 "$file_path" 2>/dev/null)
if [ "$formatted" != "$(cat "$file_path")" ]; then
  emit_warning "pg_format found formatting issues in $file_path. Fix with: pg_format --inplace --spaces 2 $file_path"
fi

# just
just --unstable --fmt --check --justfile "$file_path" > /dev/null 2>&1
if [ $? -ne 0 ]; then
  emit_warning "just --fmt found formatting issues in $file_path. Fix with: just --unstable --fmt --justfile $file_path"
fi
```

## Accumulating multiple warnings

If you have multiple checks, collect warnings and emit once at the end:

```bash
warnings=""
add_warning() {
  warnings="${warnings:+$warnings\n}$1"
}

# ... checks that call add_warning ...

if [ -n "$warnings" ]; then
  escaped=$(printf '%b' "$warnings" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "$escaped"
  },
  "continue": true
}
EOF
fi
```

## Reading the transcript (Stop / PreCompact / SessionEnd hooks)

These hooks receive a JSON payload on stdin with a `transcript_path` field pointing to the session transcript file. Read it immediately — transcript files can be deleted during session cleanup.

```bash
INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')

if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    # each line is a JSON object with .type == "user" or "assistant"
fi
```

### Transcript entry format

```json
{ "type": "user",      "message": { "content": [{ "type": "text", "text": "..." }] } }
{ "type": "assistant", "message": { "content": [{ "type": "text", "text": "..." }, { "type": "tool_use", "name": "Edit", "input": { "file_path": "..." } }] } }
```

`content` can also be a plain string for simple user messages.

### Useful jq patterns

```bash
# Last 30 user prompts (up to 3KB)
jq -r '
    select(.type == "user")
    | .message.content
    | if type == "array" then map(select(.type == "text") | .text) | join(" ")
      elif type == "string" then .
      else empty end
' "$TRANSCRIPT" | tail -30 | tail -c 3000

# First line of the last assistant text response
jq -r '
    select(.type == "assistant")
    | .message.content[]?
    | select(.type == "text")
    | .text
' "$TRANSCRIPT" | tail -1 | head -1

# Files edited via Write/Edit/MultiEdit
jq -r '
    select(.type == "assistant")
    | .message.content[]?
    | select(.type == "tool_use")
    | select(.name == "Write" or .name == "Edit" or .name == "MultiEdit")
    | .input.file_path // empty
' "$TRANSCRIPT" | sort -u
```

**Note:** `jq -r` on a JSONL file streams one result per output line across all entries — so `tail -1` on the output gives you the last match across the whole transcript, not the last field of the last entry.

## Logging

Always log to a file for debugging — hook stdout/stderr is consumed by Claude Code and not shown in the terminal:

```bash
LOG_FILE="$CLAUDE_PROJECT_DIR/.claude/hooks/myhook.log"
log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}
```
