#!/usr/bin/env python3
"""Share immutable build tools, not writable SwiftPM build directories.

stdout is the executable path; diagnostics and compiler output go to stderr.
Each content key has a process lock and is published only after a complete build.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import stat
import subprocess
import sys
import tempfile

BUILDER_FILE = Path(__file__).resolve()
# A running process cannot adopt edited Python code. Freeze its identity once;
# later on-disk edits require a new process, not a retry with the old builder.
BUILDER_DIGEST = hashlib.sha256(BUILDER_FILE.read_bytes()).hexdigest()
ROOT = BUILDER_FILE.parent.parent
SCHEMA = 1
BUILD_ENV = (
    "DEVELOPER_DIR", "TOOLCHAINS", "SDKROOT", "MACOSX_DEPLOYMENT_TARGET",
    "CC", "CXX", "CFLAGS", "CXXFLAGS", "CPPFLAGS", "LDFLAGS", "SWIFTFLAGS",
    "SWIFT_EXEC", "SWIFT_EXEC_MANIFEST", "SWIFT_DRIVER_SWIFT_FRONTEND_EXEC",
)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def progress(message: str) -> None:
    print(f"deps-graph cache: {message}", file=sys.stderr, flush=True)


def output(command: list[str]) -> str:
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout.strip()


def toolchain_identity() -> dict:
    swift = output(["xcrun", "--find", "swift"])
    # Keep effective SDK/compiler identities: a GUI and a shell may select different Xcodes.
    # Only hashes of environment values are persisted, never credentials/config contents.
    environment = {
        key: digest(value.encode())
        for key, value in os.environ.items()
        if key in BUILD_ENV or key.startswith("SWIFTPM_")
    }
    return {
        # swift is an argv[0]-dispatched symlink to swift-frontend in Xcode.
        # Resolve its target for identity, but retain the driver name to invoke SwiftPM.
        "swift": str(Path(swift).absolute()),
        "swift_target": str(Path(swift).resolve()),
        "swift_version": output([swift, "--version"]),
        "xcode": output(["xcodebuild", "-version"]),
        "sdk_path": output(["xcrun", "--sdk", "macosx", "--show-sdk-path"]),
        "sdk_version": output(["xcrun", "--sdk", "macosx", "--show-sdk-version"]),
        "platform": platform.system(),
        "os_release": platform.release(),
        "architecture": platform.machine(),
        "configuration": "release",
        "environment": environment,
    }


def package_inputs(repo: Path) -> dict[str, bytes]:
    package = repo / "tools" / "deps-graph"
    if package.is_symlink():
        raise RuntimeError(f"symlinked package is unsupported: {package}")
    files = [package / "Package.swift", package / "Package.resolved"]
    sources = package / "Sources"
    if sources.is_symlink() or not sources.is_dir():
        raise RuntimeError(f"missing deps-graph sources: {sources}")
    files += sorted(sources.rglob("*"))
    configuration = package / ".swiftpm" / "configuration"
    if configuration.exists():
        files += sorted(configuration.rglob("*"))
    inputs = {}
    for path in files:
        if path.is_symlink():
            raise RuntimeError(f"symlinked build input is unsupported: {path}")
        if path.is_dir():
            continue
        # Reading bytes, not mtimes or HEAD, includes unstaged source changes.
        inputs[path.relative_to(package).as_posix()] = path.read_bytes()
    return inputs


def require_current_builder() -> None:
    try:
        current = digest(BUILDER_FILE.read_bytes())
    except OSError as error:
        raise RuntimeError("deps-graph cache builder changed; restart preparation") from error
    if current != BUILDER_DIGEST:
        raise RuntimeError("deps-graph cache builder changed; restart preparation")


def content_key(inputs: dict[str, bytes], toolchain: dict) -> str:
    require_current_builder()
    identity = {
        "schema": SCHEMA,
        "builder": BUILDER_DIGEST,
        "files": {name: digest(data) for name, data in sorted(inputs.items())},
        "toolchain": toolchain,
    }
    return digest(json.dumps(identity, sort_keys=True, separators=(",", ":")).encode())


def managed_directory(path: Path) -> None:
    if path.is_symlink():
        raise RuntimeError(f"refusing symlinked cache directory: {path}")
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not path.is_dir():
        raise RuntimeError(f"cache path is not a directory: {path}")


@contextmanager
def key_lock(path: Path):
    # Never unlink lock files: a waiter could otherwise lock a different inode.
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            progress(f"waiting for builder ({path.stem[:12]})")
            fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def cached_executable(entry: Path, key: str) -> Path | None:
    binary = entry / "deps-graph"
    manifest = entry / "ready.json"
    if entry.is_symlink() or binary.is_symlink() or manifest.is_symlink():
        raise RuntimeError(f"refusing symlinked cache entry: {entry}")
    try:
        info = json.loads(manifest.read_text())
        binary_stat = binary.stat()
        if (
            info.get("schema") == SCHEMA
            and info.get("key") == key
            and stat.S_ISREG(binary_stat.st_mode)
            and binary_stat.st_mode & 0o111
            and info.get("sha256") == digest(binary.read_bytes())
        ):
            return binary
    except (OSError, ValueError, AttributeError):
        pass
    return None


def build_tool(snapshot: Path, scratch: Path, toolchain: dict) -> Path:
    command = [
        toolchain["swift"], "build", "-c", "release", "--product", "deps-graph",
        "--package-path", str(snapshot), "--scratch-path", str(scratch),
        "--force-resolved-versions", "--skip-update",
    ]
    subprocess.run(command, check=True, stdout=sys.stderr, stderr=sys.stderr)
    bin_path = output(command + ["--show-bin-path"])
    binary = Path(bin_path) / "deps-graph"
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise RuntimeError("Swift build did not produce an executable deps-graph")
    return binary


def ensure_deps_graph(
    repo: Path,
    cache: Path,
    *,
    identity_provider=toolchain_identity,
    builder=build_tool,
) -> Path:
    cache = cache.expanduser().resolve()
    tools = cache / "deps-graph"
    locks = tools / "locks"
    entries = tools / "entries"
    managed_directory(cache)
    managed_directory(tools)
    managed_directory(locks)
    managed_directory(entries)
    for _ in range(3):
        identity = identity_provider()
        inputs = package_inputs(repo)
        key = content_key(inputs, identity)
        entry = entries / key
        with key_lock(locks / (key + ".lock")):
            if content_key(package_inputs(repo), identity_provider()) != key:
                progress("inputs changed while waiting; retrying")
                continue
            hit = cached_executable(entry, key)
            if hit is not None:
                if content_key(package_inputs(repo), identity_provider()) != key:
                    progress("inputs changed during cache validation; retrying")
                    continue
                progress(f"hit {key[:12]}")
                return hit
            if entry.exists():
                progress(f"repairing incomplete/corrupt entry {key[:12]}")
                if entry.is_dir():
                    shutil.rmtree(entry)
                else:
                    entry.unlink()
            progress(f"building {key[:12]} (private SwiftPM workspace)")
            with tempfile.TemporaryDirectory(prefix=f".{key}.pending-", dir=tools) as temporary:
                stage = Path(temporary)
                snapshot = stage / "source"
                for name, data in inputs.items():
                    target = snapshot / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(data)
                binary = builder(snapshot, stage / "build", identity)
                if content_key(package_inputs(repo), identity_provider()) != key:
                    progress("inputs changed during build; discarding result and retrying")
                    continue
                publish = stage / "publish"
                publish.mkdir()
                target = publish / "deps-graph"
                shutil.copyfile(binary, target)
                target.chmod(0o555)
                manifest = {
                    "schema": SCHEMA,
                    "key": key,
                    "sha256": digest(target.read_bytes()),
                }
                (publish / "ready.json").write_text(json.dumps(manifest, sort_keys=True) + "\n")
                require_current_builder()
                publish.rename(entry)
            progress(f"published {key[:12]}")
            return entry / "deps-graph"
    raise RuntimeError("deps-graph inputs kept changing; retry after edits finish")


def default_cache_root() -> Path:
    override = os.environ.get("STET_WORKTREE_CACHE_DIR")
    if override:
        return Path(override)
    return Path(os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")) / "stet/worktrees/v1"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tool", choices=["deps-graph"])
    args = parser.parse_args()
    try:
        print(ensure_deps_graph(ROOT, default_cache_root()), flush=True)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"deps-graph cache: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
