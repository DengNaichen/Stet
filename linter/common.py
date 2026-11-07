# Adapted from HarnessKit shared-memory, documentation lint (0a7261f2).
"""Shared diagnostics and read-only repository path handling."""

from __future__ import annotations

import os
import stat
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Diagnostic:
    path: str
    code: str
    message: str
    line: int = 1

    def __str__(self) -> str:
        return f"{self.path}:{self.line}: {self.code}: {self.message}"


class PrerequisiteError(ValueError):
    """The checker cannot run; this is not a checked-source violation."""


def git(root: Path, *args: str) -> bytes:
    # Do not refresh/write the index, run a pager, or inherit an unrelated index.
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_OPTIONAL_LOCKS="0", GIT_TERMINAL_PROMPT="0")
    try:
        result = subprocess.run(
            ["git", "-c", "core.fsmonitor=false", "-C", str(root), *args],
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise PrerequisiteError(f"cannot read Git repository: {exc}") from exc
    if result.returncode:
        raise PrerequisiteError(result.stderr.decode("utf-8", "replace").strip())
    return result.stdout


def repository_root(candidate: Path) -> Path:
    raw = git(candidate, "rev-parse", "--show-toplevel")
    return Path(os.fsdecode(raw.rstrip(b"\n"))).resolve()


def tracked_files(root: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    for record in git(root, "ls-files", "--stage", "-z").split(b"\0"):
        if not record:
            continue
        metadata, path = record.split(b"\t", 1)
        mode, _oid, stage = metadata.split()
        name = os.fsdecode(path)
        if stage != b"0":
            raise PrerequisiteError(f"unmerged Git index entry: {name}")
        entries[name] = mode.decode("ascii")
    return entries


def candidate_files(root: Path, tracked: dict[str, str]) -> list[str]:
    untracked = {
        os.fsdecode(path)
        for path in git(root, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0")
        if path
    }
    return sorted(set(tracked) | untracked)


def safe_target(root: Path, relative: str, allow_symlinks: bool = False) -> Path:
    """Resolve an existing path exactly, without allowing traversal outside root.

    Directory entry names are compared exactly even on case-insensitive hosts.
    Markdown may link through an internal alias; manifest files may not.
    Symlink contents are resolved component-by-component, before any file read.
    """
    if "\x00" in relative or "\\" in relative or Path(relative).is_absolute():
        raise ValueError(f"not a repository-relative path: {relative!r}")
    root = root.resolve()
    remaining = relative.split("/")
    current = root
    links = 0
    while remaining:
        part = remaining.pop(0)
        if part in ("", "."):
            continue
        if part == "..":
            if current == root:
                raise ValueError("path escapes the repository")
            current = current.parent
            continue
        try:
            with os.scandir(current) as directory:
                names = {entry.name for entry in directory}
        except OSError as exc:
            raise ValueError(f"cannot inspect {current.relative_to(root)}: {exc.strerror}") from exc
        if part not in names:
            matches = sorted(name for name in names if name.lower() == part.lower())
            if matches:
                raise ValueError(f"path case mismatch: {part!r}; on disk: {matches[0]!r}")
            raise ValueError(f"target does not exist: {relative}")
        candidate = current / part
        try:
            mode = candidate.lstat().st_mode
        except OSError as exc:
            raise ValueError(f"cannot inspect target: {exc.strerror}") from exc
        if stat.S_ISLNK(mode):
            if not allow_symlinks:
                raise ValueError(f"symlink is not allowed: {candidate.relative_to(root)}")
            links += 1
            if links > 40:
                raise ValueError("symlink cycle or too many symlinks")
            target = os.readlink(candidate)
            if os.path.isabs(target):
                # An absolute alias must already name a path inside this root.
                try:
                    target = str(Path(target).relative_to(root))
                except ValueError as exc:
                    raise ValueError("symlink target escapes the repository") from exc
                current = root
            remaining = target.split("/") + remaining
            continue
        if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
            raise ValueError(f"target is not a regular file or directory: {relative}")
        current = candidate
    return current

