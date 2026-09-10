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


def fingerprint(path):
    digest = hashlib.sha256()
    if path.is_dir():
        # Xcode also watches directory membership for assets and file groups.
        digest.update(b"directory\0")
        for name in sorted(child.name for child in path.iterdir()):
            digest.update(name.encode() + b"\0")
    else:
        digest.update(b"file\0")
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    return digest.hexdigest()


def save(root, manifest):
    entries = {}
    for relative in tracked_inputs(root):
        path = root / relative
        entries[str(relative)] = {
            "sha256": fingerprint(path),
            "mtime_ns": path.stat().st_mtime_ns,
        }
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps(entries, sort_keys=True))
    print(f"Saved timestamps for {len(entries)} tracked build inputs")


def restore(root, manifest):
    if not manifest.is_file():
        print("No input timestamps cached; using a fresh build")
        return
    entries = json.loads(manifest.read_text())
    restored = 0
    # Intersect with today's tracked inputs: removed/untracked paths and paths
    # outside the repository can never be restored from cache metadata.
    for relative in tracked_inputs(root):
        entry = entries.get(str(relative))
        path = root / relative
        if entry and entry["sha256"] == fingerprint(path):
            os.utime(path, ns=(path.stat().st_atime_ns, entry["mtime_ns"]))
            restored += 1
    print(f"Restored timestamps for {restored} unchanged build inputs")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("save", "restore"))
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    {"save": save, "restore": restore}[args.operation](Path.cwd(), args.manifest)
