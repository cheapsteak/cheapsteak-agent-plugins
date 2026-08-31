"""Repo facts for the derived block. Best-effort; never raises."""

from __future__ import annotations

import subprocess
from pathlib import Path


def _git(root: Path, *args: str) -> str | None:
    try:
        out = subprocess.run(
            ["git", "-C", str(root), *args],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    return out.stdout.strip()


def collect(root: Path) -> dict[str, str]:
    sha = _git(root, "rev-parse", "--short=7", "HEAD")
    if sha is None:
        return {}
    result = {"sha": sha}

    branch = _git(root, "rev-parse", "--abbrev-ref", "HEAD")
    if branch is not None:
        result["branch"] = "(detached)" if branch == "HEAD" else branch

    status = _git(root, "status", "--porcelain")
    if status is not None:
        result["dirty"] = "clean" if status == "" else "uncommitted changes"

    return result
