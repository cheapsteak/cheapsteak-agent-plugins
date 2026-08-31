import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
import stop
from live_report.document import STAMP_TEMPLATE, open_questions


class OpenQuestionsTest(unittest.TestCase):
    def test_finds_numbers_in_ascending_order(self):
        text = "## Waiting on you\n\nQ12 — later\n\nQ7 — earlier\n"
        self.assertEqual(open_questions(text), [7, 12])

    def test_none_when_nothing_is_waiting(self):
        self.assertEqual(open_questions("## Waiting on you\n\nNothing.\n"), [])

    def test_ignores_answered_questions_in_the_log_section(self):
        self.assertEqual(open_questions("no waiting section here\nQ3 — x\n"), [])


class QuestionShapeTest(unittest.TestCase):
    """Every markdown shape a model plausibly renders a question in.

    The parser matched exactly one — a bare `Q7` under an ATX heading — and
    returned [] for all the rest, including the shape SKILL.md's own skeleton
    renders section names in. [] is indistinguishable from "this worktree
    needs nothing", so the failure mode was total silence in the one place
    where silence is the signal. SKILL.md now also ships one exact template;
    this is the second defence, not a substitute for it.
    """

    HEADINGS = (
        "## Waiting on you",
        "### Waiting on you",
        "**Waiting on you**",
        "2. **Waiting on you**",
        "- **Waiting on you**",
        "## **Waiting on you**",
    )
    QUESTIONS = (
        "Q7 — pick one",
        "- Q7 — pick one",
        "* Q7 — pick one",
        "1. Q7 — pick one",
        "**Q7** — pick one",
        "**Q7 — pick one**",
        "### Q7 — pick one",
        "- **Q7** — pick one",
    )

    def test_every_combination_of_section_and_question_shape_is_found(self):
        for heading in self.HEADINGS:
            for question in self.QUESTIONS:
                with self.subTest(heading=heading, question=question):
                    self.assertEqual(open_questions(f"{heading}\n\n{question}\n"), [7])

    def test_a_question_rendered_as_a_heading_does_not_end_its_own_section(self):
        # The boundary scan terminates on any heading, so accepting `###` in
        # front of a question would otherwise make the FIRST question close
        # the section and hide every question after it.
        text = "## Waiting on you\n\n### Q7 — one\n\n### Q9 — two\n"
        self.assertEqual(open_questions(text), [7, 9])

    def test_the_next_section_still_ends_the_scan_when_it_is_a_heading(self):
        text = "## Waiting on you\n\nQ7 — one\n\n## Where things stand\n\nQ9 — done\n"
        self.assertEqual(open_questions(text), [7])

    def test_the_next_section_still_ends_the_scan_when_it_is_bold(self):
        text = (
            "**Waiting on you**\n\nQ7 — one\n\n"
            "**Where things stand**\n\nQ9 — answered last week\n"
        )
        self.assertEqual(open_questions(text), [7])

    def test_the_skill_skeleton_shape_is_parseable(self):
        # SKILL.md renders the section list as bold numbered items; a document
        # written to match it must not read as empty.
        text = (
            "1. The derived block\n"
            "2. **Waiting on you**\n\n"
            "   Q7 — pick one\n\n"
            "3. **Where things stand**\n"
        )
        self.assertEqual(open_questions(text), [7])


class WaitingPrintTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.plugin = self.root / "plugin"
        self.home = self.root / "home"
        (self.root / ".agent" / "live-report").mkdir(parents=True)
        self.plugin.mkdir()
        self.home.mkdir()
        (self.plugin / "config.default.json").write_text(
            json.dumps({"cap_lines": 40, "floor_turns": 10})
        )

    def doc(self, turn, body=""):
        (self.root / ".agent" / "live-report" / "on").touch()
        (self.root / ".agent" / "live-report" / "status.md").write_text(
            STAMP_TEMPLATE.format(timestamp="t", turn=turn, session_id="s1")
            + "\n"
            + body
        )

    def run_hook(self, turn):
        return stop.main(
            {"session_id": "s1", "hook_event_name": "Stop", "cwd": str(self.root)},
            root=self.root,
            plugin_root=self.plugin,
            home=self.home,
        )

    def test_prints_when_a_question_appears(self):
        self.doc(1, "## Waiting on you\n\nQ7 — pick one\n")
        out = self.run_hook(1)
        self.assertIn("waiting on you", out["systemMessage"])
        self.assertIn("Q7", out["systemMessage"])
        self.assertIn(str(self.root / ".agent" / "live-report" / "status.md"), out["systemMessage"])

    def test_silent_when_the_set_is_unchanged(self):
        self.doc(1, "## Waiting on you\n\nQ7 — pick one\n")
        self.run_hook(1)
        self.doc(2, "## Waiting on you\n\nQ7 — pick one\n")
        out = self.run_hook(2) or {}
        self.assertNotIn("systemMessage", out)

    def test_silent_when_nothing_is_waiting(self):
        self.doc(1, "## Waiting on you\n\nNothing.\n")
        out = self.run_hook(1) or {}
        self.assertNotIn("systemMessage", out)

    def test_prints_again_when_the_set_changes(self):
        self.doc(1, "## Waiting on you\n\nQ7 — pick one\n")
        self.run_hook(1)
        self.doc(2, "## Waiting on you\n\nQ7 — pick one\n\nQ9 — and this\n")
        out = self.run_hook(2)
        self.assertIn("Q9", out["systemMessage"])

    def test_message_names_every_open_question_not_a_selected_one(self):
        # Q7 is still pending AND Q9 just arrived — the message must carry
        # both, not just the new one (Q9) or just the lowest one (Q7).
        self.doc(1, "## Waiting on you\n\nQ7 — pick one\n")
        self.run_hook(1)
        self.doc(2, "## Waiting on you\n\nQ7 — pick one\n\nQ9 — and this\n")
        out = self.run_hook(2)
        self.assertIn("Q7", out["systemMessage"])
        self.assertIn("Q9", out["systemMessage"])


if __name__ == "__main__":
    unittest.main()
