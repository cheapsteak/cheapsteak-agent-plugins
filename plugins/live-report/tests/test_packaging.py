"""The plugin's shape, as the marketplace and the hook runtime see it."""

import json
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
        self.assertEqual(self.manifest["name"], "live-report")

    def test_has_an_author(self):
        self.assertTrue(self.manifest["author"]["name"])

    def test_carries_no_version(self):
        # Claude Code names the cache folder after `version` but does not
        # rewrite the user's install pin when it changes, so a bump dangles
        # the pin and the plugin stops loading. Unversioned plugins are keyed
        # on the commit SHA instead. See anthropics/claude-code#52218.
        self.assertNotIn("version", self.manifest)


class HooksManifestTest(unittest.TestCase):
    def setUp(self):
        self.hooks = json.loads((ROOT / "hooks" / "hooks.json").read_text())["hooks"]

    def test_registers_exactly_the_two_events(self):
        self.assertEqual(set(self.hooks), {"Stop", "SessionStart"})

    def test_every_command_is_plugin_root_relative_and_exists(self):
        for event, matchers in self.hooks.items():
            for matcher in matchers:
                for hook in matcher["hooks"]:
                    with self.subTest(event=event):
                        cmd = hook["command"]
                        self.assertIn("${CLAUDE_PLUGIN_ROOT}", cmd)
                        rel = cmd.split("${CLAUDE_PLUGIN_ROOT}/", 1)[1].rstrip('"')
                        self.assertTrue((ROOT / rel).exists(), rel)


class MarketplaceTest(unittest.TestCase):
    def setUp(self):
        entries = json.loads(
            (REPO / ".claude-plugin" / "marketplace.json").read_text()
        )["plugins"]
        self.entry = next(e for e in entries if e["name"] == "live-report")

    def test_source_points_at_this_directory(self):
        self.assertEqual(self.entry["source"], "./plugins/live-report")

    def test_entry_carries_no_version(self):
        self.assertNotIn("version", self.entry)


class LayoutTest(unittest.TestCase):
    def test_components_do_not_live_inside_the_manifest_directory(self):
        # A documented mistake: Claude Code discovers `skills/` and `hooks/`
        # at the plugin root, not under `.claude-plugin/`.
        for name in ("skills", "hooks", "commands"):
            self.assertFalse((ROOT / ".claude-plugin" / name).exists(), name)


if __name__ == "__main__":
    unittest.main()
