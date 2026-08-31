import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "hooks"))
from live_report.config import CONFIG_KEYS
from live_report.document import TAGS, open_questions

SKILL = ROOT / "skills" / "live-report" / "SKILL.md"
STOP = ROOT / "hooks" / "stop.py"


class SyncFenceTest(unittest.TestCase):
    def test_config_default_keys_match_the_code(self):
        shipped = set(json.loads((ROOT / "config.default.json").read_text()))
        self.assertEqual(shipped, set(CONFIG_KEYS))

    def test_skill_documents_exactly_the_known_tags(self):
        text = SKILL.read_text()
        documented = {
            t
            for t in ("DECISION", "BLOCKED", "PARKED", "RESOLVED", "READY")
            if f"`{t} —`" in text
        }
        self.assertEqual(documented, set(TAGS))

    def test_the_skill_template_is_what_the_parser_actually_reads(self):
        """Both halves of the C3 fix, fenced against each other.

        SKILL.md ships one exact template so the model has a single shape to
        reproduce, and the parser is loosened so the shapes it doesn't
        reproduce still work. Neither half helps if the template itself
        parses to [] — which is precisely how the original shipped: the
        skeleton rendered section names as bold numbered list items, a shape
        the parser returned nothing for, and nothing anywhere compared the
        two. [] is indistinguishable from "nothing is waiting".
        """
        text = SKILL.read_text()
        start = text.index("## Waiting on you")
        fenced = text[start:].split("```markdown", 1)[1].split("```", 1)[0]
        self.assertIn("Waiting on you", fenced)
        self.assertEqual(open_questions(fenced), [7, 9])

    def test_skill_names_the_hook_as_the_source_of_the_session_id(self):
        """The stamp mandates a session id the model has no other way to
        learn. Both hooks now state it; the skill has to say so, or the model
        invents one and every later turn reads as a foreign session."""
        text = SKILL.read_text()
        self.assertIn("SessionStart", text)
        self.assertIn("Never invent one", text)

    def test_the_concurrent_owner_phrase_the_skill_quotes_is_the_one_emitted(self):
        """SKILL.md tells the model to stop writing when the hook says this in
        these words. A quoted phrase that has drifted from the emitter is
        worse than no quote: it makes the one case where overwriting is
        genuinely destructive unrecognisable."""
        quoted = '"Another session is live in this worktree and owns'
        self.assertIn(quoted, SKILL.read_text())
        self.assertIn(quoted.lstrip('"'), STOP.read_text())

    def test_skill_documents_exactly_three_verbs(self):
        text = SKILL.read_text()
        self.assertIn("`/live-report`", text)
        self.assertIn("`/live-report off`", text)
        self.assertIn("`/live-report update`", text)
        self.assertNotIn("`/live-report status`", text)


if __name__ == "__main__":
    unittest.main()
