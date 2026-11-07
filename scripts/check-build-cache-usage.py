#!/usr/bin/env python3
"""Refuse cache cleanup only for processes associated with the target checkout/resources."""
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys


BUILD_TOOLS = {
    "Xcode", "xcodebuild", "xcode-build-server", "XCBBuildService", "SWBBuildService",
    "sourcekit-lsp", "SourceKitService", "swift", "swift-build", "swift-test",
    "swift-package", "swift-driver", "swiftc", "swift-frontend", "xctest",
}


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, timeout=15)


def process_snapshot():
    result = run("/bin/ps", "-axo", "pid=,ppid=,args=")
    if result.returncode:
        raise RuntimeError("Unable to inspect processes; preserving build caches.")
    processes = {}
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) != 3 or not parts[0].isdigit() or not parts[1].isdigit():
            raise RuntimeError("Incomplete process snapshot; preserving build caches.")
        processes[int(parts[0])] = (int(parts[1]), parts[2])
    if not processes:
        raise RuntimeError("Empty process snapshot; preserving build caches.")
    return processes


def associated_path(path, roots):
    path = str(Path(path).resolve())
    return any(path == root or path.startswith(root + "/") for root in roots)


def check_usage(checkout, caches):
    roots = {str(Path(path).resolve()) for path in [checkout, *caches]}
    processes = process_snapshot()
    # The cleaner and its launchers necessarily mention the target in their command lines.
    ancestors = set()
    pid = os.getpid()
    while pid and pid not in ancestors:
        ancestors.add(pid)
        pid = processes.get(pid, (0, ""))[0]
    for pid, (_, command) in processes.items():
        if pid in ancestors:
            continue
        if any(re.search(re.escape(root) + r'''(?=$|[/\s"'])''', command) for root in roots):
            raise RuntimeError(f"Process {pid} references the target checkout or cache; stop it before cleanup.")
        try:
            args = shlex.split(command)
        except ValueError:
            args = command.split()
        if any(
            associated_path(arg.split("=", 1)[-1], roots)
            for arg in args if arg.split("=", 1)[-1].startswith("/")
        ):
            raise RuntimeError(f"Process {pid} references the target checkout or cache; stop it before cleanup.")
        if not args:
            continue
        executable = Path(args[0]).name
        tool = executable
        if executable.startswith("python") and len(args) > 1:
            tool = Path(args[1]).name
        if tool not in BUILD_TOOLS:
            continue
        files = run("/usr/sbin/lsof", "-nP", "-a", "-p", str(pid), "-Fpn")
        if files.returncode or not files.stdout.strip():
            # Processes can finish between ps and lsof. Only ignore confirmed exits.
            alive = run("/bin/ps", "-p", str(pid), "-o", "pid=")
            if alive.returncode == 1 and not alive.stdout.strip():
                continue
            raise RuntimeError(f"Unable to inspect {tool} (PID {pid}); preserving build caches.")
        for line in files.stdout.splitlines():
            if line.startswith("n/") and associated_path(line[1:], roots):
                raise RuntimeError(f"{tool} (PID {pid}) is using {line[1:]}; stop it before cleanup.")


def main():
    if len(sys.argv) < 2:
        print("usage: check-build-cache-usage.py <checkout> [cache ...]", file=sys.stderr)
        return 2
    try:
        check_usage(sys.argv[1], sys.argv[2:])
    except (OSError, subprocess.TimeoutExpired, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
