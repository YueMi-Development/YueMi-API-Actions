#!/usr/bin/env python3
"""Generate markdown release notes from git history."""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path


def run_git(args: list[str]) -> str:
    result = subprocess.run(
        ["git"] + args,
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout.strip()


def get_previous_tag(full_tag: str) -> str | None:
    """Return the most recent full version tag before full_tag."""
    tags = run_git(["tag", "--list", "v[0-9]*.[0-9]*.[0-9]*", "--sort=-v:refname"])
    candidates = [t for t in tags.splitlines() if t and t != full_tag]
    return candidates[0] if candidates else None


def get_commits(start_ref: str | None, end_ref: str) -> list[str]:
    """Return one-line commit summaries between start_ref and end_ref."""
    args = ["log", "--pretty=format:%s"]
    if start_ref:
        args.append(f"{start_ref}..{end_ref}")
    else:
        args.append("--max-count=50")
    output = run_git(args)
    return [line.strip() for line in output.splitlines() if line.strip()]


def categorize_commits(commits: list[str]) -> dict[str, list[str]]:
    categories: dict[str, list[str]] = {
        "Features": [],
        "Bug Fixes": [],
        "Documentation": [],
        "Maintenance": [],
        "Other Changes": [],
    }

    pattern = re.compile(r"^(feat|fix|docs|chore|ci|build|refactor|test|style)(?:\(.+\))?!?:\s*(.+)$", re.IGNORECASE)

    for commit in commits:
        match = pattern.match(commit)
        if match:
            prefix = match.group(1).lower()
            message = match.group(2)
            if prefix == "feat":
                categories["Features"].append(message)
            elif prefix == "fix":
                categories["Bug Fixes"].append(message)
            elif prefix == "docs":
                categories["Documentation"].append(message)
            elif prefix in {"chore", "ci", "build", "refactor", "test", "style"}:
                categories["Maintenance"].append(message)
            else:
                categories["Other Changes"].append(commit)
        else:
            categories["Other Changes"].append(commit)

    return {k: v for k, v in categories.items() if v}


def generate_notes(version: str, output: Path) -> None:
    full_tag = f"v{version.lstrip('v')}"
    previous_tag = get_previous_tag(full_tag)
    commits = get_commits(previous_tag, "HEAD")

    if not commits:
        body = f"## Release {full_tag}\n\nNo new commits since {previous_tag or 'the beginning'}.\n"
        output.write_text(body, encoding="utf-8")
        return

    categories = categorize_commits(commits)

    lines = [f"## Release {full_tag}", ""]

    repo = os.environ.get("GITHUB_REPOSITORY")
    if not repo:
        origin = run_git(["remote", "get-url", "origin"])
        for prefix in ("https://github.com/", "git@github.com:"):
            if origin.startswith(prefix):
                repo = origin[len(prefix):].replace(".git", "")
                break

    if previous_tag and repo:
        lines.append(f"Changes since [{previous_tag}](https://github.com/{run_git(['remote', 'get-url', 'origin']).replace('https://github.com/', '').replace('.git', '')}/compare/{previous_tag}...{full_tag}):\n")

    for section, items in categories.items():
        lines.append(f"### {section}")
        for item in items:
            lines.append(f"- {item}")
        lines.append("")

    output.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate release notes from git history")
    parser.add_argument("--version", required=True, help="Version to release (e.g. 1.0.0)")
    parser.add_argument("--output", default="RELEASE_NOTES.md", help="Output file path")
    args = parser.parse_args()

    output_path = Path(args.output)
    generate_notes(args.version, output_path)
    print(f"Release notes written to {output_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
