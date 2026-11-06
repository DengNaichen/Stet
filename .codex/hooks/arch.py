#!/usr/bin/env python3
"""Architecture hook for Claude Code and Codex (same JSON hook protocol).

Host adapter only; rules and checks live in scripts/arch-check.py.

  Stop  if StetMac/ has working-tree changes, run the check. On new violations,
        block once and feed back the violations together with the rules, so
        the agent learns the rules only when it needs them (nothing is injected
        at session start). Never block twice in a row.

Errors never pass silently: when the check cannot run, the turn is blocked
once with instructions, then the hook gives up with a visible message.
Python 3.9 compatible (desktop hosts may resolve /usr/bin/python3).
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

MAX_INPUT_BYTES = 1024 * 1024
MAX_FEEDBACK_CHARS = 6000
CHECK_TIMEOUT_S = 90


def emit(value: dict) -> None:
    sys.stdout.write(json.dumps(value, ensure_ascii=False) + "\n")


def bounded(text: str, limit: int = MAX_FEEDBACK_CHARS) -> str:
    text = (text or "").strip()
    return text if len(text) <= limit else text[:limit] + "\n… output truncated"


def parse_input() -> dict:
    raw = sys.stdin.read(MAX_INPUT_BYTES + 1)
    if len(raw.encode()) > MAX_INPUT_BYTES:
        raise ValueError("hook payload exceeds 1 MiB")
    value = json.loads(raw or "{}")
    if not isinstance(value, dict):
        raise ValueError("hook payload must be a JSON object")
    return value


def repo_root(event: dict) -> Path:
    cwd = event.get("cwd") or "."
    out = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True)
    if out.returncode != 0 or not out.stdout.strip():
        raise RuntimeError("hook cwd is not inside a Git worktree")
    return Path(out.stdout.strip()).resolve()


def should_give_up(event: dict) -> bool:
    if event.get("stop_hook_active") is True:
        return True
    count = event.get("loop_count")
    return isinstance(count, int) and count >= 1


def changed_paths(root: Path) -> list[str]:
    """Working-tree paths, including both sides of renames (porcelain v1 -z)."""
    out = subprocess.run(
        ["git", "-C", str(root), "status", "--porcelain=v1", "-z", "--untracked-files=all"],
        capture_output=True, text=True, timeout=10,
    )
    if out.returncode != 0:
        raise RuntimeError(f"git status failed: {bounded(out.stderr, 500)}")
    entries = out.stdout.split("\0")
    paths: list[str] = []
    i = 0
    while i < len(entries):
        entry = entries[i]
        i += 1
        if not entry:
            continue
        if len(entry) < 4 or entry[2] != " ":
            raise RuntimeError("malformed git status record")
        paths.append(entry[3:])
        if "R" in entry[:2] or "C" in entry[:2]:
            paths.append(entries[i])
            i += 1
    return paths


def run_check(root: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(root / "scripts" / "arch-check.py"), *args],
                          cwd=root, capture_output=True, text=True, timeout=CHECK_TIMEOUT_S)


def block_or_give_up(event: dict, reason: str) -> None:
    reason = bounded(reason)
    if should_give_up(event):
        emit({"systemMessage": reason
              + "\nArchitecture hook will not continue this turn again; issues remain."})
    else:
        emit({"decision": "block", "reason": reason})


def stop(event: dict, root: Path) -> None:
    if not (root / "scripts" / "arch-check.py").exists():
        emit({})
        return
    relevant = [p for p in changed_paths(root) if p.startswith("StetMac/") and p.endswith(".swift")]
    if not relevant:
        emit({})
        return
    if not (root / "tools" / "deps-graph" / ".build" / "release" / "deps-graph").exists():
        block_or_give_up(event, (
            "Architecture check not run: tools/deps-graph is not built. Build it with "
            "`swift build -c release --package-path tools/deps-graph` (about 3 minutes; use a "
            "long command timeout), then run `python3 scripts/arch-check.py --new-only` and fix "
            "any new violations before reporting success."))
        return
    result = run_check(root, "--json")
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        block_or_give_up(event, "Architecture check failed to run:\n" + result.stderr
                         + "\nRun `python3 scripts/arch-check.py --new-only` manually.")
        return
    if data["new"] == 0:
        note = f"Architecture check passed: no new violations ({data['baseline']} baselined)."
        if data["fixed"]:
            note += (f" {len(data['fixed'])} baseline entries are fixed; remove them from "
                     "scripts/arch-baseline.json.")
        emit({"systemMessage": note})
        return
    rules = run_check(root, "--print-rules").stdout.strip()
    # Violations first: if the feedback is truncated, the rules are cut, not the errors.
    block_or_give_up(event, (
        f"Architecture check found {data['new']} new violation(s) in this change. Fix them, "
        "rerun `python3 scripts/arch-check.py --new-only` until it reports 0 new, then report. "
        "Do not add entries to scripts/arch-baseline.json.\n\n"
        + data["report"] + "\n\n" + rules))


def main() -> None:
    event: dict = {}
    try:
        event = parse_input()
        name = event.get("hook_event_name")
        if name != "Stop":
            emit({})
            return
        stop(event, repo_root(event))
    except Exception as error:  # never fail silently
        message = (f"Architecture hook did not complete: {error}. "
                   "Run `python3 scripts/arch-check.py --new-only` manually.")
        block_or_give_up(event, message)


if __name__ == "__main__":
    main()
