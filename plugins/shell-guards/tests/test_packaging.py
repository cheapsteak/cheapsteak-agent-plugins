"""The plugin's shape, as the marketplace and the hook runtime see it."""

import json
import os
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]


class PluginManifestTest(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads(
            (ROOT / ".claude-plugin" / "plugin.json").read_text()
        )

    def test_name(self):
        self.assertEqual(self.manifest["name"], "shell-guards")

    def test_has_an_author(self):
        self.assertTrue(self.manifest["author"]["name"])

    def test_carries_no_version(self):
        # Claude Code names the cache folder after `version` but does not
        # rewrite the user's install pin when it changes, so a bump dangles
        # the pin and the plugin stops loading. See anthropics/claude-code#52218.
        self.assertNotIn("version", self.manifest)


class HooksManifestTest(unittest.TestCase):
    def setUp(self):
        self.hooks = json.loads((ROOT / "hooks" / "hooks.json").read_text())["hooks"]

    def test_registers_only_pre_tool_use_on_bash(self):
        self.assertEqual(set(self.hooks), {"PreToolUse"})
        self.assertEqual([m["matcher"] for m in self.hooks["PreToolUse"]], ["Bash"])

    def test_every_command_is_plugin_root_relative_and_executable(self):
        for event, matchers in self.hooks.items():
            for matcher in matchers:
                for hook in matcher["hooks"]:
                    with self.subTest(event=event):
                        cmd = hook["command"]
                        self.assertIn("${CLAUDE_PLUGIN_ROOT}", cmd)
                        rel = cmd.split("${CLAUDE_PLUGIN_ROOT}/", 1)[1].rstrip('"')
                        path = ROOT / rel
                        self.assertTrue(path.is_file(), rel)
                        self.assertTrue(os.access(path, os.X_OK), rel)
                        self.assertTrue(
                            path.read_text().startswith("#!/usr/bin/env python3\n")
                        )


class MarketplaceTest(unittest.TestCase):
    def setUp(self):
        entries = json.loads(
            (REPO / ".claude-plugin" / "marketplace.json").read_text()
        )["plugins"]
        self.entry = next(e for e in entries if e["name"] == "shell-guards")

    def test_source_points_at_this_directory(self):
        self.assertEqual(self.entry["source"], "./plugins/shell-guards")

    def test_entry_carries_no_version(self):
        self.assertNotIn("version", self.entry)


class LayoutTest(unittest.TestCase):
    def test_components_do_not_live_inside_the_manifest_directory(self):
        for name in ("skills", "hooks", "commands"):
            self.assertFalse((ROOT / ".claude-plugin" / name).exists(), name)


if __name__ == "__main__":
    unittest.main()
