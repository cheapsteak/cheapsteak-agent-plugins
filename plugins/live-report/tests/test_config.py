import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
from live_report.config import CONFIG_KEYS, load_config


class LoadConfigTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        self.plugin = self.root / "plugin"
        self.home = self.root / "home"
        self.wt = self.root / "wt"
        for d in (self.plugin, self.home, self.wt / ".agent" / "live-report"):
            d.mkdir(parents=True)
        (self.plugin / "config.default.json").write_text(
            json.dumps({"cap_lines": 40, "floor_turns": 10})
        )

    def _load(self):
        return load_config(self.wt, plugin_root=self.plugin, home=self.home)

    def test_defaults_when_no_overrides(self):
        self.assertEqual(self._load(), {"cap_lines": 40, "floor_turns": 10})

    def test_machine_layer_overrides_default(self):
        p = self.home / ".config" / "live-report"
        p.mkdir(parents=True)
        (p / "config.json").write_text(json.dumps({"cap_lines": 60}))
        self.assertEqual(self._load()["cap_lines"], 60)
        self.assertEqual(self._load()["floor_turns"], 10)

    def test_worktree_layer_wins(self):
        p = self.home / ".config" / "live-report"
        p.mkdir(parents=True)
        (p / "config.json").write_text(json.dumps({"cap_lines": 60}))
        (self.wt / ".agent" / "live-report" / "config.json").write_text(
            json.dumps({"cap_lines": 25})
        )
        self.assertEqual(self._load()["cap_lines"], 25)

    def test_malformed_layer_is_ignored_not_fatal(self):
        p = self.home / ".config" / "live-report"
        p.mkdir(parents=True)
        (p / "config.json").write_text("{not json")
        self.assertEqual(self._load()["cap_lines"], 40)

    def test_unknown_keys_are_dropped(self):
        (self.wt / ".agent" / "live-report" / "config.json").write_text(
            json.dumps({"nonsense": 1})
        )
        self.assertEqual(set(self._load()), CONFIG_KEYS)


if __name__ == "__main__":
    unittest.main()
