"""The guard, driven through the real script with hook JSON on stdin."""

import json
import subprocess
import sys
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "hooks" / "bash_guard.py"


def run(stdin: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT)],
        input=stdin,
        capture_output=True,
        text=True,
        timeout=10,
    )


def run_command(command: str) -> subprocess.CompletedProcess:
    payload = {
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "tool_input": {"command": command},
    }
    return run(json.dumps(payload))


# (command, text the stderr reason must contain)
BLOCKED = [
    ('pkill -f "poll_pr.py 123 --until ready" -n -0', "`-n`"),
    ("pgrep -f foo -l", "`-l`"),
    ("sudo pkill -f foo -9", "`-9`"),
    ("x=$(pgrep -f foo -n)", "`-n`"),
    ('true && pkill -f "a b" -0', "`-0`"),
    ("pkill -- foo -n", "`-n`"),
    ("/usr/bin/pkill -f foo -n", "`-n`"),
    ("echo start; pkill -f foo -n", "`-n`"),
    ("cd /tmp\npkill -f foo -n", "`-n`"),
    ("ps aux | pgrep -f foo -n", "`-n`"),
    ("pkill -U someone foo -n", "`-n`"),
    ('for p in a b; do pkill -f "$p" -n; done', "`-n`"),
    ('while true; do pgrep -f foo -n; sleep 1; done', "`-n`"),
    ('echo "$(pgrep -f foo -n)"', "`-n`"),
    (
        'for pid in $(pgrep -f "x.fifo"); do pp=$(ps -o ppid= -p $pid); '
        "kill $pp $pid; done",
        "ppid",
    ),
    ("kill $(ps -o ppid= -p 123)", "ppid"),
    ('kill -9 "$(ps -oppid= -p $$)"', "ppid"),
    ("ps -o pid,ppid -p 123; kill 456", "ppid"),
]

ALLOWED = [
    'pkill -n -f "poll_pr.py 123 --until ready"',
    "pkill -9 -f foo",
    "pkill -TERM -f foo",
    "pkill -f foo 2>/dev/null",
    "pkill -f foo >/dev/null 2>&1",
    "pgrep -lf foo | head",
    "pkill -F /tmp/pidfile",
    "pkill -u someone -f foo",
    "kill 12345",
    "kill -TERM 12345",
    "ps -o pid,ppid,command",
    "killall Finder",
    'echo "pkill -f foo -n"',
    'git commit -m "fix pkill -f usage -n"',
    "ls -la",
]


class BlockedTest(unittest.TestCase):
    def test_blocked(self):
        for command, reason in BLOCKED:
            with self.subTest(command=command):
                result = run_command(command)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("shell-guards: blocked", result.stderr)
                self.assertIn(reason, result.stderr)
                self.assertEqual(result.stdout, "")

    def test_pkill_message_explains_the_fix(self):
        result = run_command("pkill -f foo -n")
        self.assertIn("another pattern", result.stderr)
        self.assertIn("before the pattern", result.stderr)

    def test_ppid_message_says_it_is_coarse(self):
        result = run_command("kill $(ps -o ppid= -p 123)")
        self.assertIn("coarse", result.stderr)
        self.assertIn("exact pid", result.stderr)


class AllowedTest(unittest.TestCase):
    def test_allowed(self):
        for command in ALLOWED:
            with self.subTest(command=command):
                result = run_command(command)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr, "")


class FailOpenTest(unittest.TestCase):
    def test_inputs_that_are_not_a_command(self):
        cases = {
            "non-JSON": "not json at all",
            "empty stdin": "",
            "empty command": json.dumps({"tool_input": {"command": ""}}),
            "no command": json.dumps({"tool_input": {}}),
            "no tool_input": json.dumps({"tool_name": "Bash"}),
            "non-string command": json.dumps({"tool_input": {"command": 5}}),
            "unbalanced quote": json.dumps(
                {"tool_input": {"command": 'pkill -f "foo -n'}}
            ),
        }
        for name, stdin in cases.items():
            with self.subTest(case=name):
                result = run(stdin)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
