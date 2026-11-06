#!/usr/bin/env python3
"""Prepare the architecture tool; report app build prerequisites separately."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = Path("Packages/StetEngine/Vendor/FunASRPackage/Artifacts/FunASRRuntime.xcframework")


def progress(message: str) -> None:
    print(f"setup-worktree: {message}", file=sys.stderr, flush=True)


def output(command: list[str]) -> str:
    return subprocess.check_output(command, cwd=ROOT, text=True).strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--if-needed", action="store_true",
        help="reuse valid cached tools (inputs are checked on every invocation)",
    )
    parser.parse_args()
    started = time.monotonic()
    if sys.version_info < (3, 9):
        raise RuntimeError("Python 3.9 or newer is required")
    progress(f"checking prerequisites in {ROOT}")
    if not (ROOT / "Stet.xcodeproj").is_dir():
        raise RuntimeError("setup script is not inside a Stet checkout")
    swift = output(["xcrun", "--find", "swift"])
    xcodebuild = output(["xcrun", "--find", "xcodebuild"])
    swift_version = output([swift, "--version"]).splitlines()[0]
    xcode_version = output([xcodebuild, "-version"]).replace("\n", "; ")
    progress(f"selected {xcode_version}; {swift_version}")
    progress("preparing deps-graph (matching cache entries are reused)")
    binary = Path(output([sys.executable, str(ROOT / "scripts/worktree-cache.py"), "deps-graph"]))
    if not binary.is_absolute() or not binary.is_file() or not os.access(binary, os.X_OK):
        raise RuntimeError("deps-graph preparation did not return an executable path")
    progress(f"architecture tool ready: {binary}")
    if not (ROOT / RUNTIME).is_dir():
        progress(
            "WARNING: app builds are not ready: FunASRRuntime.xcframework is missing. "
            "Prepare the ignored runtime with "
            "Packages/StetEngine/Vendor/FunASRPackage/build-xcframework.sh "
            "before make build/test."
        )
    else:
        progress("local FunASR runtime directory present (not rebuilt or shared by setup)")
    progress(f"architecture preparation completed in {time.monotonic() - started:.2f}s; app build not run")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        progress(f"preparation failed (exit {error.returncode}); rerun after resolving the reported error")
        raise SystemExit(error.returncode if error.returncode > 0 else 1)
    except (OSError, RuntimeError) as error:
        progress(str(error))
        raise SystemExit(1)
