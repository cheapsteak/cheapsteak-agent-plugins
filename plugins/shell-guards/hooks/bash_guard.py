#!/usr/bin/env python3
# plugins/shell-guards/hooks/bash_guard.py
"""PreToolUse hook on Bash: block kill commands that hit unrelated processes.

Two command shapes are blocked:

  1. pkill/pgrep with an option AFTER the pattern. BSD (macOS) pkill and
     pgrep stop option parsing at the first pattern, so a later `-n` or `-0`
     becomes another pattern, and every process whose command line contains
     "-n" or "-0" matches. `pgrep -f nomatch` finds nothing; `pgrep -f nomatch
     -n -0` finds most of the machine.
  2. kill together with `ps -o ppid`. The parent of a Bash-tool shell is the
     agent's own process, so killing a "parent pid" from a loop kills the
     session that ran it. This rule is deliberately coarse.

A block is exit code 2 with the reason on stderr, which Claude Code shows to
the model. Everything else exits 0 silently, including malformed input: this
hook must never be the reason an ordinary command cannot run.
"""

from __future__ import annotations

import json
import os
import shlex
import sys

PKILL_NAMES = {"pkill", "pgrep"}
# BSD pkill/pgrep options that consume the following argument.
PKILL_VALUED = set("FGgPstUuc")
# Words that may precede the command word of a simple command.
PREFIX_WORDS = {
    "do", "then", "else", "elif", "if", "while", "until", "!", "{", "}",
    "time", "exec", "nohup", "command", "builtin", "xargs",
}
SUDO_VALUED = set("ugCphrtUD")
PUNCT = "();<>|&\n`"


def tokenize(command: str) -> list[str]:
    lexer = shlex.shlex(command, posix=True, punctuation_chars=PUNCT)
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    return list(lexer)


def is_punct(token: str) -> bool:
    return bool(token) and all(c in PUNCT for c in token)


def is_redirect(token: str) -> bool:
    return is_punct(token) and ("<" in token or ">" in token)


def simple_commands(command: str) -> list[list[str]]:
    """Split a command line into simple commands (lists of words).

    Redirections and their targets are dropped. Text inside a quoted `$(...)`
    is scanned again as its own command line, since the shell runs it.
    """
    try:
        tokens = tokenize(command)
    except ValueError:
        return []
    commands: list[list[str]] = []
    current: list[str] = []
    skip_next = False
    for token in tokens:
        if skip_next:
            skip_next = False
            continue
        if is_redirect(token):
            skip_next = True
            continue
        if is_punct(token):
            if current:
                commands.append(current)
            current = []
            continue
        if "$(" in token:
            inner = token.split("$(", 1)[1]
            commands.extend(simple_commands(inner.rstrip(")")))
        current.append(token)
    if current:
        commands.append(current)
    return commands


def command_word(words: list[str]) -> tuple[str, list[str]]:
    """Return (basename of the command word, its arguments)."""
    i = 0
    while i < len(words):
        word = words[i]
        if word in PREFIX_WORDS or _is_assignment(word):
            i += 1
            continue
        if os.path.basename(word) == "sudo":
            i += 1
            while i < len(words) and words[i].startswith("-"):
                flag = words[i]
                i += 1
                if flag == "--":
                    break
                if flag[-1] in SUDO_VALUED and not flag.startswith("--"):
                    i += 1
            continue
        return os.path.basename(word), words[i + 1:]
    return "", []


def _is_assignment(word: str) -> bool:
    name, eq, _ = word.partition("=")
    return bool(eq) and name.isidentifier()


def option_after_pattern(args: list[str]) -> str | None:
    """Return the first option that follows the pattern, if any."""
    i = 0
    seen_pattern = False
    end_of_options = False
    while i < len(args):
        arg = args[i]
        i += 1
        if seen_pattern:
            if arg.startswith("-") and len(arg) > 1:
                return arg
            continue
        if end_of_options or not arg.startswith("-") or arg == "-":
            seen_pattern = True
            continue
        if arg == "--":
            end_of_options = True
            continue
        letters = arg[1:]
        if letters in PKILL_VALUED:
            i += 1  # value is the next argument
            continue
        # Signal forms (-9, -TERM, -SIGTERM) are single tokens.
        if letters.isdigit() or letters.isupper():
            continue
        for j, letter in enumerate(letters):
            if letter in PKILL_VALUED:
                if j == len(letters) - 1:
                    i += 1  # value is the next argument
                break
    return None


def reads_ppid(args: list[str]) -> bool:
    for i, arg in enumerate(args):
        if not arg.startswith("-") or arg.startswith("--"):
            continue
        if "ppid" in arg:
            return True
        if arg[-1] in "oO" and i + 1 < len(args) and "ppid" in args[i + 1]:
            return True
    return False


def check(command: str) -> str | None:
    """Return a block reason, or None to allow."""
    has_kill = False
    has_ppid = False
    for words in simple_commands(command):
        name, args = command_word(words)
        if name in PKILL_NAMES:
            option = option_after_pattern(args)
            if option is not None:
                return (
                    f"shell-guards: blocked `{name}` with option `{option}` after "
                    f"the pattern. macOS {name} stops reading options at the first "
                    f"pattern, so `{option}` is treated as another pattern and "
                    f"matches every process whose command line contains "
                    f"\"{option}\" -- this has killed unrelated processes. Put "
                    f"every option before the pattern, e.g. "
                    f"`{name} {option} -f \"<pattern>\"`."
                )
        elif name == "kill":
            has_kill = True
        elif name == "ps" and reads_ppid(args):
            has_ppid = True
    if has_kill and has_ppid:
        return (
            "shell-guards: blocked `kill` in a command that reads a parent pid "
            "with `ps -o ppid`. The parent of this shell is the agent's own "
            "process, so killing a parent pid can kill the session running the "
            "command. This is a deliberately coarse rule. Kill the exact pid you "
            "started instead (for example, record `$!` when you launch a "
            "background job), and inspect parent pids in a separate command "
            "without `kill`."
        )
    return None


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read())
        command = payload["tool_input"]["command"]
    except Exception:
        return 0
    if not isinstance(command, str) or not command.strip():
        return 0
    try:
        reason = check(command)
    except Exception:
        return 0
    if reason is None:
        return 0
    sys.stderr.write(reason + "\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
