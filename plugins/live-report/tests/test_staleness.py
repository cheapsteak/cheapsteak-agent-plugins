import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
from live_report.document import Stamp, parse_stamp
from live_report.staleness import evaluate

HEAD = "abc1234"


def verdict(stamp, turn=25, head=HEAD, last=HEAD, floor=10, session="s1", owner=""):
    return evaluate(
        stamp=stamp,
        current_turn=turn,
        current_head=head,
        head_at_last_write=last,
        floor_turns=floor,
        session_id=session,
        owner_session=owner,
    )


class ParseStampTest(unittest.TestCase):
    def test_parses_a_well_formed_stamp(self):
        s = parse_stamp(
            "intro\nlast updated: 2026-08-29T10:00:00Z · turn 14 · session s1\nrest"
        )
        self.assertEqual((s.turn, s.session_id), (14, "s1"))

    def test_absent_stamp_is_none(self):
        self.assertIsNone(parse_stamp("no stamp here"))

    def test_malformed_turn_is_none(self):
        self.assertIsNone(parse_stamp("last updated: x · turn banana · session s1"))

    def test_last_stamp_wins_when_duplicated(self):
        text = (
            "last updated: a · turn 1 · session s1\n"
            "last updated: b · turn 9 · session s1"
        )
        self.assertEqual(parse_stamp(text).turn, 9)


class EvaluateTest(unittest.TestCase):
    def test_missing_stamp_is_stale(self):
        v = verdict(None)
        self.assertTrue(v.stale)
        self.assertIn("no stamp", v.reason)

    def test_current_turn_stamp_clears_the_block(self):
        self.assertFalse(verdict(Stamp("t", 25, "s1")).stale)

    def test_floor_reached_is_stale(self):
        v = verdict(Stamp("t", 15, "s1"), turn=25, floor=10)
        self.assertTrue(v.stale)
        self.assertIn("10 turns", v.reason)

    def test_one_below_floor_is_fresh(self):
        self.assertFalse(verdict(Stamp("t", 16, "s1"), turn=25, floor=10).stale)

    def test_head_moved_is_stale(self):
        v = verdict(Stamp("t", 24, "s1"), turn=25, head="deadbee", last=HEAD)
        self.assertTrue(v.stale)
        self.assertIn("HEAD", v.reason)

    def test_foreign_session_reports_and_does_not_block(self):
        # Genuinely concurrent: the recorded owner is another session AND that
        # same session wrote the document last.
        v = verdict(Stamp("t", 1, "other"), turn=25, owner="other")
        self.assertTrue(v.foreign_session)
        self.assertFalse(v.stale)

    def test_restart_is_not_a_foreign_session(self):
        # The normal case, and the one the first implementation got wrong: a
        # new session in the same worktree inherits a stamp naming the session
        # that is gone. Nobody is recorded as owner, so this is a takeover and
        # ordinary staleness applies — never the absorbing foreign_session
        # state, which forbids the one write that would repair it.
        v = verdict(Stamp("t", 1, "gone"), turn=25, owner="")
        self.assertFalse(v.foreign_session)
        self.assertTrue(v.stale)

    def test_previous_owner_that_has_been_taken_over_is_not_foreign(self):
        # This session already claimed ownership (SessionStart, or an earlier
        # Stop); the stamp still names the session it took over from. That is
        # not two live writers, it is one.
        v = verdict(Stamp("t", 1, "gone"), turn=25, session="s1", owner="s1")
        self.assertFalse(v.foreign_session)
        self.assertTrue(v.stale)

    def test_owner_that_disagrees_with_the_stamp_is_not_foreign(self):
        # A third id in the owner slot with a stamp naming somebody else means
        # neither of them is demonstrably live. Claim rather than freeze.
        v = verdict(Stamp("t", 1, "gone"), turn=25, session="s1", owner="s2")
        self.assertFalse(v.foreign_session)

    def test_exit_condition_beats_head_moved(self):
        self.assertFalse(verdict(Stamp("t", 25, "s1"), turn=25, head="deadbee").stale)

    def test_foreign_session_wins_over_the_exit_condition(self):
        # This test pins the check order: foreign-session (2) must be checked
        # before exit-condition (3). A regression that swapped them would
        # incorrectly treat a foreign session's matching-turn stamp as this
        # session's own exit condition.
        v = verdict(Stamp("t", 25, "other"), owner="other")
        self.assertTrue(v.foreign_session)
        self.assertFalse(v.stale)


if __name__ == "__main__":
    unittest.main()
