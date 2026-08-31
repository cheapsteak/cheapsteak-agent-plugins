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
import stop
from live_report.document import STAMP_TEMPLATE


class StopHookTest(unittest.TestCase):
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
        base = {"session_id": "s1", "hook_event_name": "Stop", "cwd": str(self.root)}
        base.update(payload)
        return stop.main(base, root=self.root, plugin_root=self.plugin, home=self.home)

    def write_marker(self):
        (self.root / ".agent" / "live-report" / "on").touch()

    def write_doc(self, turn, session="s1", marker=True):
        if marker:
            self.write_marker()
        (self.root / ".agent" / "live-report" / "status.md").write_text(
            STAMP_TEMPLATE.format(timestamp="t", turn=turn, session_id=session) + "\n"
        )

    def doc_text(self):
        return (self.root / ".agent" / "live-report" / "status.md").read_text()

    def state_path(self):
        return self.root / ".agent" / "live-report" / "state.json"

    def write_state(self, **fields):
        data = {}
        if self.state_path().exists():
            data = json.loads(self.state_path().read_text())
        data.update(fields)
        self.state_path().write_text(json.dumps(data))

    def read_state(self):
        return json.loads(self.state_path().read_text())

    def test_silent_when_not_opted_in(self):
        self.assertIsNone(self.run_hook())

    def test_silent_when_marker_absent_but_document_present(self):
        # The gate is the marker's existence, not the document's. A worktree
        # with a document but no `.agent/live-report/on` must still be a
        # single existence test and nothing else — no state write, no read.
        self.write_doc(1, marker=False)
        self.assertFalse((self.root / ".agent" / "live-report" / "on").exists())
        doc_before = self.doc_text()
        out = self.run_hook()
        self.assertIsNone(out)
        self.assertFalse(self.state_path().exists(), "marker-absent path wrote state")
        self.assertEqual(self.doc_text(), doc_before, "marker-absent path wrote doc")

    def test_marker_present_document_present_behaves_as_before(self):
        # The companion case: with the marker present, the hook must run its
        # real logic rather than bail out — proven here by a real, non-silent
        # side effect (state written) rather than merely "not None".
        self.write_doc(1)
        self.assertTrue((self.root / ".agent" / "live-report" / "on").exists())
        out = self.run_hook()
        self.assertTrue(self.state_path().exists(), "marker-present path did not run")
        self.assertTrue(out is None or out.get("decision") != "block")

    def test_bails_out_for_subagent_payloads(self):
        # Drive the state past the floor first, so a normal payload is
        # PROVABLY non-silent (decision: block) — otherwise assertIsNone
        # under a subagent signal is indistinguishable from "ran fully and
        # had nothing to say", which is exactly what let all three guards
        # get deleted without failing this test.
        self.write_doc(1)
        for _ in range(11):
            baseline = self.run_hook()
        self.assertEqual(
            baseline["decision"], "block", "sanity: state must be block-worthy"
        )

        state_before = self.state_path().read_text()
        doc_before = self.doc_text()

        for key, val in (
            ("agent_id", "a"),
            ("agent_type", "general-purpose"),
            ("hook_event_name", "SubagentStop"),
        ):
            out = self.run_hook(**{key: val})
            self.assertIsNone(out, key)
            # A bail-out that still performs I/O is not a bail-out.
            self.assertEqual(
                self.state_path().read_text(),
                state_before,
                f"{key}: state file touched",
            )
            self.assertEqual(self.doc_text(), doc_before, f"{key}: document touched")

    def test_bails_out_when_stop_hook_active(self):
        self.write_doc(1)
        for _ in range(11):
            baseline = self.run_hook()
        self.assertEqual(
            baseline["decision"], "block", "sanity: state must be block-worthy"
        )

        state_before = self.state_path().read_text()
        doc_before = self.doc_text()

        out = self.run_hook(stop_hook_active=True)
        self.assertIsNone(out)
        self.assertEqual(self.state_path().read_text(), state_before)
        self.assertEqual(self.doc_text(), doc_before)

    def test_blocks_when_stamp_is_behind_the_floor(self):
        self.write_doc(1)
        for _ in range(11):
            out = self.run_hook()
        self.assertEqual(out["decision"], "block")
        self.assertIn("status.md", out["reason"])

    def test_does_not_block_while_fresh(self):
        self.write_doc(1)
        out = self.run_hook()
        self.assertTrue(out is None or out.get("decision") != "block")

    def test_a_restart_claims_ownership_and_resumes_blocking(self):
        # THE case this plugin exists inside a worktree for. A session dies,
        # a new one starts, and the document it inherits is stamped by a
        # session id that will never appear again. Treating that as a live
        # foreign owner was an absorbing state reached on the happy path:
        # never stale, never blocked, and all three surfaces forbidding the
        # one write that would repair it. It must instead be a takeover.
        self.write_doc(1, session="gone")
        for _ in range(11):
            out = self.run_hook()
        self.assertEqual(out["decision"], "block")
        self.assertEqual(self.read_state()["owner_session"], "s1")

    def test_a_restart_can_actually_clear_the_block_it_is_given(self):
        # The other half: having taken over, the compliant stamp — with THIS
        # session's id, which the block reason names — clears the block.
        self.write_doc(1, session="gone")
        for _ in range(11):
            out = self.run_hook()
        self.assertEqual(out["decision"], "block")
        self.write_doc(int(out["reason"].split("stamp turn ")[1].split()[0]))
        out = self.run_hook()
        self.assertTrue(out is None or out.get("decision") != "block")

    def test_concurrent_foreign_session_reports_without_blocking(self):
        # Genuinely concurrent: the state file records another session as
        # owner AND that same session wrote the document last. Two live
        # writers, which is the only shape that must not be overwritten.
        self.write_doc(1, session="other")
        self.write_state(turn=30, owner_session="other")
        out = self.run_hook()
        self.assertNotEqual((out or {}).get("decision"), "block")
        self.assertIn(
            "Another session is live in this worktree",
            out["hookSpecificOutput"]["additionalContext"],
        )

    def test_concurrent_foreign_session_does_not_steal_ownership(self):
        self.write_doc(1, session="other")
        self.write_state(turn=30, owner_session="other")
        self.run_hook()
        self.assertEqual(self.read_state()["owner_session"], "other")

    def test_concurrent_foreign_session_document_is_left_unchanged(self):
        self.write_doc(1, session="other")
        self.write_state(turn=30, owner_session="other")
        before = self.doc_text()
        self.run_hook()
        self.assertEqual(self.doc_text(), before)

    def test_block_reason_names_the_session_id_to_stamp_with(self):
        # The model has no other source for it: no environment variable
        # carries it, and the only id in the document belongs to whoever
        # stamped last. A guessed id reads as a foreign session on every
        # later turn, which kills the guard silently.
        self.write_doc(1)
        for _ in range(11):
            out = self.run_hook()
        self.assertEqual(out["decision"], "block")
        self.assertIn("session s1", out["reason"])

    def test_over_cap_warns_but_never_blocks(self):
        # The cap is "the forcing function for the whole design", and it was
        # loaded and interpolated into the reason string without ever being
        # compared against anything — so the first attempt's measured failure
        # (708 lines) was guarded only by a rule in a prompt. It warns; it
        # must never block, because going over is permitted when going over
        # is right.
        body = "\n".join(f"line {i}" for i in range(80))
        self.write_doc(1)
        (self.root / ".agent" / "live-report" / "status.md").write_text(
            STAMP_TEMPLATE.format(timestamp="t", turn=1, session_id="s1") + "\n" + body
        )
        out = self.run_hook()
        self.assertNotEqual((out or {}).get("decision"), "block")
        ctx = out["hookSpecificOutput"]["additionalContext"]
        self.assertIn("81 lines", ctx)
        self.assertIn("cap of 40", ctx)
        self.assertIn("Where things stand", ctx)

    def test_under_cap_says_nothing_about_the_cap(self):
        self.write_doc(1)
        out = self.run_hook() or {}
        self.assertNotIn("cap of", json.dumps(out))

    def test_over_cap_rides_along_with_a_block_rather_than_replacing_it(self):
        self.write_doc(1)
        body = "\n".join(f"line {i}" for i in range(80))
        (self.root / ".agent" / "live-report" / "status.md").write_text(
            STAMP_TEMPLATE.format(timestamp="t", turn=1, session_id="s1") + "\n" + body
        )
        for _ in range(11):
            out = self.run_hook()
        self.assertEqual(out["decision"], "block")
        self.assertIn("cap of 40", out["reason"])

    def test_a_floor_of_zero_cannot_block_every_turn(self):
        # `floor_turns` is hand-edited in a local file with no review
        # step. Unclamped, 0 makes `current_turn - stamp.turn >= floor` true
        # on the very turn the model just stamped — a block every single turn
        # from a plausible typo.
        (self.root / ".agent" / "live-report" / "config.json").write_text(
            json.dumps({"floor_turns": 0})
        )
        self.write_doc(1)
        out = self.run_hook()
        self.assertTrue(out is None or out.get("decision") != "block")

    def test_malformed_payload_is_silent_not_fatal(self):
        self.write_doc(1)
        self.assertIsNone(
            stop.main({}, root=self.root, plugin_root=self.plugin, home=self.home)
        )

    @mock.patch("live_report.facts.collect")
    def test_compliant_model_clears_block_on_the_following_invocation(
        self, mock_collect
    ):
        # Regression for the off-by-one where the bookkeeping comparison ran
        # against the counter AFTER it was incremented: a model that stamps
        # exactly the turn named in the block reason could never satisfy it,
        # head_at_last_write froze at its first captured value, and every
        # later HEAD move blocked a fully compliant model forever.
        mock_collect.side_effect = [
            {"sha": "aaa0001"},
            {"sha": "bbb0002"},
            {"sha": "ccc0003"},
            {"sha": "ddd0004"},
        ]
        self.write_doc(1)
        self.run_hook()  # turn 1: baseline capture
        self.run_hook()  # turn 2: grace turn, still fresh
        out = self.run_hook()  # turn 3: HEAD has moved twice with no re-stamp
        self.assertEqual(out["decision"], "block")

        # The compliant model does exactly what the block reason asked.
        self.write_doc(3)
        out = self.run_hook()  # turn 4: the very next invocation
        self.assertTrue(
            out is None or out.get("decision") != "block",
            "a compliant re-stamp must clear the block on the following turn",
        )

    @mock.patch("live_report.facts.collect")
    def test_onboarding_does_not_block_with_zero_commits(self, mock_collect):
        # head_at_last_write starts "" (no state file yet) while a real repo
        # reports a real, non-empty sha. A model that stamped the document
        # before the first Stop invocation (turn 0) must not be blocked on
        # its very first turn purely because the counters start misaligned.
        mock_collect.return_value = {
            "sha": "abc1234",
            "branch": "main",
            "dirty": "clean",
        }
        self.write_doc(0)
        out = self.run_hook()
        self.assertTrue(out is None or out.get("decision") != "block")

    def test_run_survives_a_broken_live_report_import(self):
        self.write_doc(1)
        payload = {"session_id": "s1", "hook_event_name": "Stop", "cwd": str(self.root)}
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
            rc = stop._run()

        self.assertEqual(rc, 0)
        self.assertEqual(captured.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
