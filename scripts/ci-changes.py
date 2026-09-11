#!/usr/bin/env python3
"""Choose CI jobs from the complete Git diff, without GitHub path-filter limits."""

import argparse
import json
import os
from pathlib import Path
import subprocess


COMPATIBILITY = "StetMac/Resources/app-compatibility.json"
MACOS_ROOTS = ("StetMac/", "StetMacTests/", "StetMacUITests/", "StetVisuals/")
IOS_SWIFT_ROOTS = (
    "StetMobile/StetKeyboard/", "StetMobile/StetLiveActivity/",
    "StetMobile/StetMobile/", "StetMobile/StetMobileTests/",
    "StetMobile/StetMobileUITests/",
)
FULL_CI = {
    "Makefile", ".github/workflows/monorepo-ci.yml",
    "scripts/ci-changes.py", "scripts/tests/test_ci_changes.py",
}


def classify(paths):
    selected = {"quality": False, "macos": False, "workflows": False}
    for path in paths:
        if path in FULL_CI:
            selected.update(quality=True, macos=True, workflows=True)
        elif path.startswith(".github/workflows/"):
            selected["workflows"] = True
        elif path in (".swiftlint.yml", ".swift-format"):
            selected["quality"] = True
        elif path == COMPATIBILITY:
            # Validated on Linux, including revision monotonicity.
            continue
        elif path.startswith(MACOS_ROOTS):
            selected["macos"] = True
            selected["quality"] |= path.endswith(".swift")
        elif path.startswith("StetMobile/"):
            # iOS simulator builds remain a local Xcode Beta check.
            selected["quality"] |= path.startswith(IOS_SWIFT_ROOTS) and path.endswith(".swift")
        elif path.startswith(("docs/", "reference/", "research/", ".agents/", ".claude/", ".codex/", ".cursor/")):
            continue
        elif path.endswith(".md") or path in ("LICENSE", ".gitignore", "buildServer.json"):
            continue
        elif path.startswith(("Packages/", "Stet.xcodeproj/")) or path == "Info.plist":
            selected["macos"] = True
        elif path in ("scripts/validate-app-compatibility.py", "scripts/validate-agent-entrypoints"):
            continue  # These execute on every run in Repository Checks.
        elif path in ("scripts/ci-source-mtimes.py", "scripts/tests/test_ci_source_mtimes.py"):
            selected["macos"] = True
        else:
            # New or unclassified inputs must not silently lose coverage.
            selected.update(quality=True, macos=True)
    return selected


def git(*args):
    return subprocess.check_output(["git", *args])


def plan(event_name, event):
    if event_name == "pull_request":
        base = event["pull_request"]["base"]["sha"]
        head = event["pull_request"]["head"]["sha"]
        # Compare the entire PR, not just its last commit. Check the merged
        # configuration against the current base revision, not the merge-base.
        diff_base = git("merge-base", base, head).decode().strip()
    elif event_name == "push":
        base = event["before"]
        head = event["after"]
        if not base.strip("0"):
            # A new branch has no previous configuration. Check every file.
            paths = os.fsdecode(git("ls-tree", "-r", "--name-only", "-z", head)).split("\0")[:-1]
            return {**classify(paths), "base_ref": "", "paths": paths}
        diff_base = base
    else:
        raise ValueError(f"Unsupported CI event: {event_name}")

    # No rename detection: both the removed and added paths affect routing.
    # NUL delimiters preserve spaces/newlines and there is no 300-file limit.
    paths = os.fsdecode(git("diff", "--no-renames", "--name-only", "-z", diff_base, head, "--")).split("\0")[:-1]
    return {**classify(paths), "base_ref": base, "paths": paths}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event-name", default=os.environ.get("GITHUB_EVENT_NAME"), required=False)
    parser.add_argument("--event-path", default=os.environ.get("GITHUB_EVENT_PATH"), required=False)
    args = parser.parse_args()
    result = plan(args.event_name, json.loads(Path(args.event_path).read_text()))
    print(json.dumps(result, indent=2))
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a") as stream:
            for name in ("quality", "macos", "workflows"):
                stream.write(f"{name}={str(result[name]).lower()}\n")
            stream.write(f"base_ref={result['base_ref']}\n")
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary, "a") as stream:
            stream.write("## CI scope\n\nRepository Checks always run on Linux.\n\n")
            for name in ("quality", "macos", "workflows"):
                stream.write(f"- {name}: {'run' if result[name] else 'skip'}\n")
            stream.write(f"\nCompared {len(result['paths'])} changed paths.\n")


if __name__ == "__main__":
    main()
