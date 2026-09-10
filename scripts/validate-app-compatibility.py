#!/usr/bin/env python3
"""Validate the remotely distributed list and require a revision bump for edits."""
import argparse
import json
from pathlib import Path
import re
import subprocess

CONFIG = "StetMac/Resources/app-compatibility.json"


def validate(raw):
    if len(raw) > 262_144:
        raise ValueError("Configuration exceeds 256 KiB")
    value = json.loads(raw)
    if type(value.get("schemaVersion")) is not int or value["schemaVersion"] != 1:
        raise ValueError("schemaVersion must be 1")
    if type(value.get("revision")) is not int or value["revision"] < 1:
        raise ValueError("revision must be a positive integer")
    ids = value.get("bundleIDs")
    if not isinstance(ids, list) or len(ids) > 1_000:
        raise ValueError("bundleIDs must be an array with at most 1000 entries")
    if any(not isinstance(item, str) or not re.fullmatch(r"[a-z0-9._-]{1,255}", item)
           or "." not in item for item in ids):
        raise ValueError("Bundle IDs must be lowercase identifiers containing a dot")
    if len(set(ids)) != len(ids):
        raise ValueError("Duplicate Bundle IDs")
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-ref")
    args = parser.parse_args()
    current = validate(Path(CONFIG).read_bytes())
    if args.base_ref:
        previous = subprocess.run(
            ["git", "show", f"{args.base_ref}:{CONFIG}"], capture_output=True, check=False)
        if previous.returncode == 0:
            old = validate(previous.stdout)
            if current != old and current["revision"] <= old["revision"]:
                raise ValueError("Increment revision whenever the compatibility list changes")
    print(f"Compatibility revision {current['revision']}: {len(current['bundleIDs'])} valid entries")


if __name__ == "__main__":
    main()
