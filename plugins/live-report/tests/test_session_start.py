import builtins
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
import session_start
from live_report.document import STAMP_TEMPLATE


class SessionStartTest(unittest.TestCase):
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

    def run_hook(self, **payload):
        base = {
            "session_id": "s2",
            "hook_event_name": "SessionStart",
            "cwd": str(self.root),
        }
        base.update(payload)
        return session_start.main(
            base, root=self.root, plugin_root=self.plugin, home=self.home
        )

    def write_marker(self):
        (self.root / ".agent" / "live-report" / "on").touch()

    def test_silent_when_not_opted_in(self):
        self.assertIsNone(self.run_hook())

    def test_silent_when_marker_absent_but_document_present(self):
        # The gate is the marker's existence, not the document's. A worktree
        # with a document but no `.agent/live-report/on` must return None
        # and do nothing else — checked before the document is even read.
        (self.root / ".agent" / "live-report" / "status.md").write_text(
            STAMP_TEMPLATE.format(timestamp="t", turn=5, session_id="s1") + "\n"
        )
        self.assertFalse((self.root / ".agent" / "live-report" / "on").exists())
        out = self.run_hook()
        self.assertIsNone(out)

    def test_marker_present_document_present_behaves_as_before(self):
        # The companion case: with the marker present, SessionStart must
        # produce its real additionalContext rather than bail out.
        self.write_marker()
        (self.root / ".agent" / "live-report" / "status.md").write_text(
            STAMP_TEMPLATE.format(timestamp="t", turn=5, session_id="s1") + "\n"
        )
        out = self.run_hook()
        self.assertIsNotNone(out)
        self.assertIn("status.md", json.dumps(out))

    def test_points_a_new_session_at_the_document(self):
        self.write_marker()
        (self.root / ".agent" / "live-report" / "status.md").write_text(
            STAMP_TEMPLATE.format(timestamp="t", turn=5, session_id="s1") + "\n"
        )
        out = self.run_hook()
        self.assertIn("status.md", json.dumps(out))
        # Verify the actual stamped turn appears, not just the document path
        self.assertIn("turn 5", json.dumps(out))

    def test_never_blocks(self):
        """SessionStart informs; it never enforces. The 'decision' key must never
        appear in the output, regardless of path or future changes."""
        self.write_marker()
        (self.root / ".agent" / "live-report" / "status.md").write_text("no stamp\n")
        out = self.run_hook()
        self.assertNotIn("decision", out or {})

    def test_no_decision_key_when_stamp_exists(self):
        """Verify 'decision' key is absent when document has a valid stamp."""
        self.write_marker()
        (self.root / ".agent" / "live-report" / "status.md").write_text(
            STAMP_TEMPLATE.format(timestamp="t", turn=5, session_id="s1") + "\n"
        )
        out = self.run_hook()
        self.assertNotIn("decision", out or {})

    def test_no_decision_key_with_foreign_session(self):
        """Verify 'decision' key is absent even when a foreign session is detected."""
        self.write_marker()
        (self.root / ".agent" / "live-report" / "status.md").write_text(
            STAMP_TEMPLATE.format(timestamp="t", turn=5, session_id="s1") + "\n"
        )
        out = self.run_hook(session_id="s2")
        self.assertNotIn("decision", out or {})

    def test_warns_when_session_differs(self):
        """A stamp naming another session is surfaced explicitly — but as a
        takeover, not as a standoff. It used to hedge ("if that session is
        still live, reconcile"), which contradicted Stop and SKILL.md and left
        the model with no way to act on the normal case: a restart."""
        self.write_marker()
        (self.root / ".agent" / "live-report" / "status.md").write_text(
            STAMP_TEMPLATE.format(timestamp="t", turn=5, session_id="s1") + "\n"
        )
        out = self.run_hook(session_id="s2")
        self.assertIn("DIFFERENT session", json.dumps(out))
        self.assertIn("claimed ownership", json.dumps(out))

    def test_states_this_sessions_id_as_the_value_to_stamp_with(self):
        """The model's ONLY source for it. No environment variable carries the
        session id, and the only id in the document belongs to whoever stamped
        last — after a restart, a session that no longer exists. Copying that
        one produces a stamp that reads as foreign on every later turn."""
        self.write_marker()
        (self.root / ".agent" / "live-report" / "status.md").write_text(
            STAMP_TEMPLATE.format(timestamp="t", turn=5, session_id="s1") + "\n"
        )
        out = self.run_hook(session_id="s2")
        self.assertIn("This session's id is s2", json.dumps(out))

    def test_claims_ownership_for_the_new_session(self):
        """A session start in this worktree IS the takeover event. Without the
        claim, Stop compares against a stamp that may be days old and every
        restart reads as a live foreign owner — the freeze this fixes."""
        self.write_marker()
        (self.root / ".agent" / "live-report" / "status.md").write_text(
            STAMP_TEMPLATE.format(timestamp="t", turn=5, session_id="s1") + "\n"
        )
        self.run_hook(session_id="s2")
        state = json.loads(
            (self.root / ".agent" / "live-report" / "state.json").read_text()
        )
        self.assertEqual(state["owner_session"], "s2")

    def test_claim_preserves_the_rest_of_the_state_file(self):
        (self.root / ".agent" / "live-report" / "state.json").write_text(
            json.dumps({"turn": 12, "head_at_last_write": "abc1234"})
        )
        self.write_marker()
        (self.root / ".agent" / "live-report" / "status.md").write_text(
            STAMP_TEMPLATE.format(timestamp="t", turn=5, session_id="s1") + "\n"
        )
        self.run_hook(session_id="s2")
        state = json.loads(
            (self.root / ".agent" / "live-report" / "state.json").read_text()
        )
        self.assertEqual(state["turn"], 12)
        self.assertEqual(state["head_at_last_write"], "abc1234")

    def test_no_claim_is_written_when_the_worktree_has_not_opted_in(self):
        (self.root / ".agent" / "live-report" / "status.md").write_text(
            STAMP_TEMPLATE.format(timestamp="t", turn=5, session_id="s1") + "\n"
        )
        self.run_hook(session_id="s2")
        self.assertFalse((self.root / ".agent" / "live-report" / "state.json").exists())

    def test_does_not_warn_when_session_matches(self):
        """When the stamp's session matches the payload's session, the foreign-session
        warning must be absent."""
        self.write_marker()
        (self.root / ".agent" / "live-report" / "status.md").write_text(
            STAMP_TEMPLATE.format(timestamp="t", turn=5, session_id="s2") + "\n"
        )
        out = self.run_hook(session_id="s2")
        self.assertNotIn("DIFFERENT session", json.dumps(out))

    def test_run_survives_a_broken_live_report_import(self):
        self.write_marker()
        (self.root / ".agent" / "live-report" / "status.md").write_text(
            STAMP_TEMPLATE.format(timestamp="t", turn=5, session_id="s1") + "\n"
        )
        payload = {
            "session_id": "s2",
            "hook_event_name": "SessionStart",
            "cwd": str(self.root),
        }
        stdin = io.StringIO(json.dumps(payload))

        orig_import = builtins.__import__

        def broken_import(name, *args, **kwargs):
            if name == "live_report" or name.startswith("live_report."):
                raise ImportError("simulated broken sibling module")
            return orig_import(name, *args, **kwargs)

        captured = io.StringIO()
        with (
            mock.patch("builtins.__import__", side_effect=broken_import),
            mock.patch.object(sys, "stdin", stdin),
            mock.patch.dict(os.environ, {"CLAUDE_PLUGIN_ROOT": str(self.plugin)}),
            contextlib.redirect_stdout(captured),
        ):
            rc = session_start._run()

        self.assertEqual(rc, 0)
        self.assertEqual(captured.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
