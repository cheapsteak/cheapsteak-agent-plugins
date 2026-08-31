import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
from live_report import facts
from live_report.document import (
    DERIVED_BEGIN,
    DERIVED_END,
    content_line_count,
    render_derived_block,
    replace_derived_block,
)


class RenderTest(unittest.TestCase):
    def _block(self):
        return render_derived_block(
            {"branch": "main", "sha": "abc1234", "dirty": "clean"},
            turn=25,
            timestamp="2026-08-29T10:00:00Z",
            log_link="./status-log.md",
        )

    def test_block_is_marker_delimited(self):
        b = self._block()
        self.assertTrue(b.startswith(DERIVED_BEGIN))
        self.assertTrue(b.rstrip().endswith(DERIVED_END))

    def test_block_carries_derived_not_last_updated(self):
        b = self._block()
        self.assertIn("derived:", b)
        self.assertNotIn("last updated:", b)

    def test_block_links_the_log(self):
        self.assertIn("./status-log.md", self._block())

    def test_replace_swaps_between_markers_only(self):
        doc = f"head\n{DERIVED_BEGIN}\nOLD\n{DERIVED_END}\ntail\n"
        out = replace_derived_block(doc, f"{DERIVED_BEGIN}\nNEW\n{DERIVED_END}")
        self.assertIn("NEW", out)
        self.assertNotIn("OLD", out)
        self.assertIn("head", out)
        self.assertIn("tail", out)

    def test_replace_prepends_when_markers_absent(self):
        out = replace_derived_block("body\n", f"{DERIVED_BEGIN}\nNEW\n{DERIVED_END}")
        self.assertTrue(out.startswith(DERIVED_BEGIN))
        self.assertIn("body", out)


class ContentLineCountTest(unittest.TestCase):
    def test_counts_content_lines(self):
        self.assertEqual(content_line_count("a\nb\nc\n"), 3)

    def test_blank_lines_do_not_count(self):
        # The skeleton is six blank-separated sections; charging the budget
        # for separators would fire the cap on documents nowhere near bloat.
        self.assertEqual(content_line_count("a\n\n\nb\n   \nc\n"), 3)

    def test_the_hook_owned_derived_block_does_not_count(self):
        # The cap is on what the MODEL writes. The derived block is written
        # and sized by the hook, so charging the model for it would be
        # charging for a section it cannot shrink.
        doc = f"{DERIVED_BEGIN}\nbranch\nsha\nderived: t\n{DERIVED_END}\na\nb\n"
        self.assertEqual(content_line_count(doc), 2)

    def test_missing_markers_are_not_fatal(self):
        self.assertEqual(content_line_count("a\nb\n"), 2)

    def test_empty_document(self):
        self.assertEqual(content_line_count(""), 0)


class FactsTest(unittest.TestCase):
    def test_collect_on_a_real_repo(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            # Identity via -c, and the ambient environment inherited rather
            # than a hand-built PATH, so whichever git is on PATH is used.
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            # git commit spawns a detached `git maintenance run --auto` that can
            # re-create .git/objects during temp-dir teardown (OSError Errno 39).
            for key, value in (
                ("maintenance.auto", "false"),
                ("gc.auto", "0"),
                ("commit.gpgsign", "false"),
            ):
                subprocess.run(
                    ["git", "-C", str(root), "config", key, value], check=True
                )
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(root),
                    "-c",
                    "user.email=t@t",
                    "-c",
                    "user.name=t",
                    "commit",
                    "-q",
                    "--allow-empty",
                    "-m",
                    "x",
                    "--no-gpg-sign",
                ],
                check=True,
            )
            f = facts.collect(root)
            self.assertEqual(len(f["sha"]), 7)
            self.assertEqual(f["dirty"], "clean")

    def test_collect_never_raises_outside_a_repo(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(facts.collect(Path(d)), {})

    def test_collect_omits_dirty_when_status_fails(self):
        """When status call fails, dirty key is omitted but branch and sha preserved."""
        root = Path("/fake")

        def _git_side_effect(_, *args):
            if args[0] == "rev-parse" and args[1] == "--short=7":
                return "abc1234"
            if args[0] == "rev-parse" and args[1] == "--abbrev-ref":
                return "main"
            if args[0] == "status":
                return None  # Simulate status call failure
            return None

        with patch("live_report.facts._git", side_effect=_git_side_effect):
            result = facts.collect(root)
            self.assertEqual(result["sha"], "abc1234")
            self.assertEqual(result["branch"], "main")
            self.assertNotIn("dirty", result)

    def test_collect_omits_branch_when_call_fails(self):
        """When branch call fails, branch key is omitted but sha preserved."""
        root = Path("/fake")

        def _git_side_effect(_, *args):
            if args[0] == "rev-parse" and args[1] == "--short=7":
                return "abc1234"
            if args[0] == "rev-parse" and args[1] == "--abbrev-ref":
                return None  # Simulate branch call failure
            if args[0] == "status":
                return ""
            return None

        with patch("live_report.facts._git", side_effect=_git_side_effect):
            result = facts.collect(root)
            self.assertEqual(result["sha"], "abc1234")
            self.assertEqual(result["dirty"], "clean")
            self.assertNotIn("branch", result)


if __name__ == "__main__":
    unittest.main()
