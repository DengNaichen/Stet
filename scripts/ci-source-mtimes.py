#!/usr/bin/env python3
"""Restore Xcode input mtimes only when tracked inputs still have identical content."""

import argparse
import hashlib
import json
from pathlib import Path
import os
import subprocess


def tracked_inputs(root):
    names = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
    paths = set()
    for name in filter(None, names):
        relative = Path(name)
        # Do not follow tracked symlinks or symlinked parent directories.
        if any((root / part).is_symlink() for part in (relative, *relative.parents)):
            continue
        path = root / relative
        if path.is_file():
            paths.add(relative)
            paths.update(parent for parent in relative.parents if parent != Path("."))
    return sorted(paths, key=str)


def fingerprint(path, cache=None):
    cache = {} if cache is None else cache
    if path in cache:
        return cache[path]
    digest = hashlib.sha256()
    if path.is_symlink():
        # A directory hash includes link text, never the external target.
        digest.update(b"symlink\0" + os.readlink(path).encode())
    elif path.is_dir():
        # A resource change must invalidate its containing directory even if
        # membership is unchanged. Memoization hashes each file only once.
        digest.update(b"directory-tree\0")
        for child in sorted(path.iterdir(), key=lambda child: child.name):
            digest.update(child.name.encode() + b"\0")
            digest.update(fingerprint(child, cache).encode())
    else:
        digest.update(b"file\0")
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    cache[path] = digest.hexdigest()
    return cache[path]


def save(root, manifest):
    entries = {}
    hashes = {}
    for relative in tracked_inputs(root):
        path = root / relative
        entries[str(relative)] = {
            "sha256": fingerprint(path, hashes),
            "mtime_ns": path.stat().st_mtime_ns,
        }
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps(entries, sort_keys=True))
    print(f"Saved timestamps for {len(entries)} tracked build inputs")


def restore(root, manifest):
    if not manifest.is_file():
        print("No input timestamps cached; using a fresh build")
        return
    try:
        entries = json.loads(manifest.read_text())
        if not isinstance(entries, dict):
            raise ValueError("Expected a timestamp map")
    except (OSError, ValueError):
        print("Invalid input timestamp cache; using fresh input timestamps")
        return
    restored = 0
    hashes = {}
    # Intersect with today's tracked inputs: removed/untracked paths and paths
    # outside the repository can never be restored from cache metadata.
    for relative in tracked_inputs(root):
        entry = entries.get(str(relative))
        path = root / relative
        if (
            isinstance(entry, dict)
            and isinstance(entry.get("mtime_ns"), int)
            and 0 <= entry["mtime_ns"] < 2**63
            and entry.get("sha256") == fingerprint(path, hashes)
        ):
            os.utime(path, ns=(path.stat().st_atime_ns, entry["mtime_ns"]))
            restored += 1
    print(f"Restored timestamps for {restored} unchanged build inputs")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("save", "restore"))
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    {"save": save, "restore": restore}[args.operation](Path.cwd(), args.manifest)
