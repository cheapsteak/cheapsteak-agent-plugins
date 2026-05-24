#!/usr/bin/env python3
"""Fetch all PR feedback (reviews, comments, threads) as structured JSON.

Wraps multiple `gh` CLI calls into a single command that can be allowlisted
in Claude Code settings. Outputs JSON to stdout for easy consumption.

Usage:
    python scripts/fetch_pr_feedback.py                  # Auto-detect PR from current branch
    python scripts/fetch_pr_feedback.py --pr-number 123  # Specific PR
    python scripts/fetch_pr_feedback.py --include-resolved  # Include resolved threads
"""

import argparse
import json
import subprocess
import sys


def run_gh(args: list[str]) -> str:
    """Run a gh CLI command and return stdout. Exit on failure."""
    try:
        result = subprocess.run(
            ["gh", *args],
            capture_output=True,
            text=True,
            check=True,
        )
    except FileNotFoundError:
        print(
            "Error: `gh` CLI not found. Install it: https://cli.github.com/",
            file=sys.stderr,
        )
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(
            f"Error running `gh {' '.join(args)}`:\n{e.stderr.strip()}", file=sys.stderr
        )
        sys.exit(1)
    return result.stdout.strip()


def run_git(args: list[str]) -> str:
    """Run a git command and return stdout."""
    try:
        result = subprocess.run(
            ["git", *args],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        print(
            f"Error running `git {' '.join(args)}`:\n{e.stderr.strip()}",
            file=sys.stderr,
        )
        return ""
    return result.stdout.strip()


def get_repo_info() -> tuple[str, str]:
    """Get owner and repo name from gh CLI."""
    raw = run_gh(["repo", "view", "--json", "owner,name"])
    data = json.loads(raw)
    return data["owner"]["login"], data["name"]


def get_pr_number() -> int:
    """Auto-detect PR number for the current branch."""
    raw = run_gh(["pr", "view", "--json", "number", "-q", ".number"])
    return int(raw)


def fetch_pr_metadata(pr_number: int) -> dict:
    """Fetch PR metadata and reviews."""
    raw = run_gh(["pr", "view", str(pr_number), "--json", "number,title,url,reviews"])
    return json.loads(raw)


def fetch_issue_comments(owner: str, repo: str, pr_number: int) -> list:
    """Fetch issue-level comments (general PR comments)."""
    raw = run_gh(
        [
            "api",
            f"repos/{owner}/{repo}/issues/{pr_number}/comments",
            "--paginate",
        ]
    )
    return json.loads(raw)


def fetch_review_threads(owner: str, repo: str, pr_number: int) -> list:
    """Fetch review threads via GraphQL.

    Fetches up to 100 threads with up to 50 comments each. Warns to stderr
    if results were truncated due to pagination limits.
    """
    query = """
query($owner: String!, $repo: String!, $prNumber: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $prNumber) {
      reviewThreads(first: 100) {
        pageInfo {
          hasNextPage
        }
        nodes {
          id
          isResolved
          isOutdated
          comments(first: 50) {
            pageInfo {
              hasNextPage
            }
            nodes {
              author {
                login
              }
              body
              path
              line
              createdAt
            }
          }
        }
      }
    }
  }
}
"""

    raw = run_gh(
        [
            "api",
            "graphql",
            "-f",
            f"query={query}",
            "-F",
            f"owner={owner}",
            "-F",
            f"repo={repo}",
            "-F",
            f"prNumber={pr_number}",
        ]
    )
    data = json.loads(raw)
    threads_data = data["data"]["repository"]["pullRequest"]["reviewThreads"]

    if threads_data["pageInfo"]["hasNextPage"]:
        print(
            "Warning: PR has more than 100 review threads; results are truncated.",
            file=sys.stderr,
        )

    for thread in threads_data["nodes"]:
        if thread.get("comments", {}).get("pageInfo", {}).get("hasNextPage"):
            thread_id = thread.get("id", "unknown")
            print(
                f"Warning: Thread {thread_id} has more than 50 comments; results are truncated.",
                file=sys.stderr,
            )

    return threads_data["nodes"]


def get_recent_commits(count: int = 10) -> list[str]:
    """Get recent commit summaries."""
    output = run_git(["log", "--oneline", f"-{count}"])
    if not output:
        return []
    return output.splitlines()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fetch all PR feedback as structured JSON"
    )
    parser.add_argument(
        "--pr-number",
        type=int,
        help="PR number (auto-detected from current branch if omitted)",
    )
    parser.add_argument(
        "--include-resolved",
        action="store_true",
        help="Include resolved review threads (default: only unresolved)",
    )
    args = parser.parse_args()

    # Determine PR number
    pr_number = args.pr_number
    if pr_number is None:
        try:
            pr_number = get_pr_number()
        except (ValueError, SystemExit):
            print(
                "Error: Could not detect PR for current branch. Use --pr-number to specify.",
                file=sys.stderr,
            )
            sys.exit(1)

    owner, repo = get_repo_info()

    # Fetch all data
    metadata = fetch_pr_metadata(pr_number)
    issue_comments_raw = fetch_issue_comments(owner, repo, pr_number)
    review_threads_raw = fetch_review_threads(owner, repo, pr_number)
    recent_commits = get_recent_commits()

    # Format reviews
    reviews = []
    for r in metadata.get("reviews", []) or []:
        reviews.append(
            {
                "author": r.get("author", {}).get("login", "unknown"),
                "state": r.get("state", ""),
                "body": r.get("body", ""),
            }
        )

    # Format issue comments
    issue_comments = []
    for c in issue_comments_raw or []:
        issue_comments.append(
            {
                "author": (c.get("user") or {}).get("login", "unknown"),
                "body": c.get("body", ""),
                "created_at": c.get("created_at", ""),
            }
        )

    # Format review threads (optionally filtering resolved)
    review_threads = []
    for t in review_threads_raw or []:
        is_resolved = t.get("isResolved", False)
        if not args.include_resolved and is_resolved:
            continue
        comments = []
        for c in t.get("comments", {}).get("nodes") or []:
            comments.append(
                {
                    "author": (c.get("author") or {}).get("login", "unknown"),
                    "body": c.get("body", ""),
                    "path": c.get("path"),
                    "line": c.get("line"),
                    "created_at": c.get("createdAt", ""),
                }
            )
        review_threads.append(
            {
                "id": t.get("id", ""),
                "is_resolved": is_resolved,
                "is_outdated": t.get("isOutdated", False),
                "comments": comments,
            }
        )

    output = {
        "pr": {
            "number": metadata["number"],
            "title": metadata["title"],
            "url": metadata["url"],
        },
        "reviews": reviews,
        "issue_comments": issue_comments,
        "review_threads": review_threads,
        "recent_commits": recent_commits,
    }

    json.dump(output, sys.stdout, indent=2)
    print()  # trailing newline


if __name__ == "__main__":
    main()
