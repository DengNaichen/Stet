import importlib.util
import json
import multiprocessing
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "worktree-cache.py"
spec = importlib.util.spec_from_file_location("worktree_cache", SCRIPT)
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)

IDENTITY = {"swift": "/fixture/swift", "version": "test-1", "architecture": "arm64"}


def make_repo(root):
    package = root / "tools/deps-graph"
    (package / "Sources/deps-graph").mkdir(parents=True)
    (package / "Package.swift").write_text("fixture package")
    (package / "Package.resolved").write_text('{"version":3,"pins":[]}')
    (package / "Sources/deps-graph/main.swift").write_text("source v1")
    return root


def fake_builder(snapshot, scratch, _identity):
    scratch.mkdir()
    binary = scratch / "deps-graph"
    binary.write_bytes((snapshot / "Sources/deps-graph/main.swift").read_bytes())
    binary.chmod(0o755)
    return binary


def concurrent_worker(repo, target, counter, gate, result_queue):
    def builder(snapshot, scratch, identity):
        with open(counter, "a") as file:
            file.write("build\n")
        time.sleep(0.15)
        return fake_builder(snapshot, scratch, identity)

    gate.wait()
    try:
        binary = cache.ensure_deps_graph(
            Path(repo), Path(target), identity_provider=lambda: IDENTITY, builder=builder,
        )
        result_queue.put((str(binary), binary.read_text()))
    except BaseException as error:
        result_queue.put(("error", repr(error)))


class WorktreeCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = make_repo(self.root / "checkout-a")
        self.store = self.root / "cache"
        self.source = self.repo / "tools/deps-graph/Sources/deps-graph/main.swift"
        self.builds = 0

    def build(self, snapshot, scratch, identity):
        self.builds += 1
        return fake_builder(snapshot, scratch, identity)

    def ensure(self, repo=None, identity=None, builder=None):
        return cache.ensure_deps_graph(
            repo or self.repo, self.store,
            identity_provider=lambda: identity or IDENTITY,
            builder=builder or self.build,
        )

    def load_private_builder_module(self, suffix=""):
        script = self.root / ("builder" + suffix + ".py")
        script.write_text(SCRIPT.read_text() + "\nTEST_BUILDER_REVISION = 1\n")
        def load():
            spec = importlib.util.spec_from_file_location("private_builder" + suffix, script)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module
        return script, load

    def test_builder_edit_during_compile_aborts_instead_of_publishing_old_code_under_new_key(self):
        script, load = self.load_private_builder_module()
        old = load()
        calls = []

        def old_builder(snapshot, scratch, identity):
            calls.append(old.TEST_BUILDER_REVISION)
            binary = fake_builder(snapshot, scratch, identity)
            binary.write_text(str(old.TEST_BUILDER_REVISION))
            script.write_text(script.read_text().replace(
                "TEST_BUILDER_REVISION = 1", "TEST_BUILDER_REVISION = 222"))
            return binary

        with self.assertRaisesRegex(RuntimeError, "builder changed.*restart"):
            old.ensure_deps_graph(
                self.repo, self.store, identity_provider=lambda: IDENTITY, builder=old_builder,
            )
        self.assertEqual(calls, [1])
        self.assertEqual(list((self.store / "deps-graph/entries").iterdir()), [])
        fresh = load()
        self.assertEqual(fresh.TEST_BUILDER_REVISION, 222)

        def fresh_builder(snapshot, scratch, identity):
            binary = fake_builder(snapshot, scratch, identity)
            binary.write_text(str(fresh.TEST_BUILDER_REVISION))
            return binary

        binary = fresh.ensure_deps_graph(
            self.repo, self.store, identity_provider=lambda: IDENTITY, builder=fresh_builder,
        )
        self.assertEqual(binary.read_text(), "222")

    def test_builder_edit_during_hot_cache_validation_does_not_return_stale_result(self):
        script, load = self.load_private_builder_module("_hot")
        old = load()
        old.ensure_deps_graph(
            self.repo, self.store, identity_provider=lambda: IDENTITY, builder=fake_builder,
        )
        original_check = old.cached_executable

        def edit_while_checking(entry, key):
            hit = original_check(entry, key)
            script.write_text(script.read_text().replace(
                "TEST_BUILDER_REVISION = 1", "TEST_BUILDER_REVISION = 222"))
            return hit

        with patch.object(old, "cached_executable", side_effect=edit_while_checking):
            with self.assertRaisesRegex(RuntimeError, "builder changed.*restart"):
                old.ensure_deps_graph(
                    self.repo, self.store, identity_provider=lambda: IDENTITY, builder=fake_builder,
                )

    def test_cache_home_unset_empty_and_explicit_paths(self):
        with patch.dict(os.environ, {}, clear=True):
            expected = Path.home() / ".cache/stet/worktrees/v1"
            self.assertEqual(cache.default_cache_root(), expected)
            os.environ["XDG_CACHE_HOME"] = ""
            self.assertEqual(cache.default_cache_root(), expected)
            os.environ["XDG_CACHE_HOME"] = "/fixture/xdg"
            self.assertEqual(cache.default_cache_root(), Path("/fixture/xdg/stet/worktrees/v1"))
            os.environ["STET_WORKTREE_CACHE_DIR"] = "/fixture/override"
            self.assertEqual(cache.default_cache_root(), Path("/fixture/override"))

    def test_swift_symlink_keeps_driver_name_for_real_builder_invocation(self):
        toolchain = self.root / "toolchain"
        toolchain.mkdir()
        frontend = toolchain / "swift-frontend"
        frontend.write_text("""#!/bin/sh
case "${0##*/}" in swift) ;; *) echo 'frontend is not the SwiftPM driver' >&2; exit 64 ;; esac
if [ "$1" = --version ]; then echo 'Swift fixture 1'; exit 0; fi
[ "$1" = build ] || exit 65
show=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --scratch-path) shift; scratch=$1 ;;
        --show-bin-path) show=true ;;
    esac
    shift
done
if [ "$show" = true ]; then printf '%s/release\\n' "$scratch"; exit 0; fi
mkdir -p "$scratch/release"
printf '#!/bin/sh\\nexit 0\\n' > "$scratch/release/deps-graph"
chmod +x "$scratch/release/deps-graph"
""")
        frontend.chmod(0o755)
        driver = toolchain / "swift"
        driver.symlink_to(frontend.name)
        real_output = cache.output

        def discovery(command):
            if command == ["xcrun", "--find", "swift"]:
                return str(driver)
            if command[0] == "xcrun":
                return "/fixture/macos-sdk" if command[-1] == "--show-sdk-path" else "26.5"
            if command == ["xcodebuild", "-version"]:
                return "Xcode fixture"
            return real_output(command)

        with patch.object(cache, "output", side_effect=discovery):
            binary = cache.ensure_deps_graph(
                self.repo, self.store, identity_provider=cache.toolchain_identity,
            )
        self.assertTrue(os.access(binary, os.X_OK))
        self.assertEqual(subprocess.run([str(binary)]).returncode, 0)

    def test_same_content_from_other_checkout_reuses_executable_without_local_build(self):
        other = self.root / "checkout-b"
        shutil.copytree(self.repo, other)
        first = self.ensure()
        second = self.ensure(other)
        self.assertEqual(first, second)
        self.assertEqual(self.builds, 1)
        self.assertEqual(second.read_text(), "source v1")
        self.assertFalse((other / "tools/deps-graph/.build").exists())
        self.assertFalse((self.repo / "tools/deps-graph/.build").exists())

    def test_dirty_source_change_invalidates_and_other_checkout_keeps_old_binary(self):
        other = self.root / "checkout-b"
        shutil.copytree(self.repo, other)
        first = self.ensure()
        self.source.write_text("source v2")
        changed = self.ensure()
        self.assertNotEqual(first, changed)
        self.assertEqual(changed.read_text(), "source v2")
        self.assertEqual(self.ensure(other), first)
        self.assertEqual(first.read_text(), "source v1")
        self.assertEqual(self.builds, 2)

    def test_lockfile_manifest_toolchain_and_source_membership_invalidate(self):
        previous = self.ensure()
        for file in ("Package.resolved", "Package.swift"):
            path = self.repo / "tools/deps-graph" / file
            path.write_text(path.read_text() + "changed")
            current = self.ensure()
            self.assertNotEqual(previous, current)
            previous = current
        extra = self.source.with_name("Extra.swift")
        extra.write_text("new declaration")
        current = self.ensure()
        self.assertNotEqual(previous, current)
        different_toolchain = self.ensure(identity={**IDENTITY, "version": "test-2"})
        self.assertNotEqual(current, different_toolchain)
        extra.unlink()
        without_extra = self.ensure(identity={**IDENTITY, "version": "test-2"})
        self.assertNotEqual(without_extra, different_toolchain)

    def test_corrupted_binary_and_manifest_are_rebuilt(self):
        binary = self.ensure()
        binary.chmod(0o755)
        binary.write_text("corrupt")
        self.assertEqual(self.ensure().read_text(), "source v1")
        self.assertEqual(self.builds, 2)
        (binary.parent / "ready.json").write_text("not json")
        self.assertEqual(self.ensure().read_text(), "source v1")
        self.assertEqual(self.builds, 3)

    def test_failed_build_never_publishes_and_can_be_retried(self):
        def fail(snapshot, scratch, identity):
            fake_builder(snapshot, scratch, identity)
            raise RuntimeError("compiler failed")

        with self.assertRaisesRegex(RuntimeError, "compiler failed"):
            self.ensure(builder=fail)
        self.assertEqual(list((self.store / "deps-graph/entries").iterdir()), [])
        self.assertEqual(list((self.store / "deps-graph").glob("*.pending-*")), [])
        self.assertEqual(self.ensure().read_text(), "source v1")

    def test_source_change_during_build_discards_stale_result(self):
        def edit_during_first_build(snapshot, scratch, identity):
            result = self.build(snapshot, scratch, identity)
            if self.builds == 1:
                self.source.write_text("source v2")
            return result

        binary = self.ensure(builder=edit_during_first_build)
        self.assertEqual(binary.read_text(), "source v2")
        self.assertEqual(self.builds, 2)
        self.assertEqual(len(list((self.store / "deps-graph/entries").iterdir())), 1)

    def test_concurrent_processes_publish_once_and_return_complete_output(self):
        other = self.root / "checkout-b"
        shutil.copytree(self.repo, other)
        context = multiprocessing.get_context("fork")
        gate = context.Event()
        result_queue = context.Queue()
        counter = self.root / "build-count"
        workers = [context.Process(
            target=concurrent_worker,
            args=(str(repo), str(self.store), str(counter), gate, result_queue),
        ) for repo in (self.repo, other)]
        for worker in workers:
            worker.start()
        gate.set()
        try:
            results = [result_queue.get(timeout=10) for _ in workers]
            for worker in workers:
                worker.join(timeout=10)
                self.assertEqual(worker.exitcode, 0)
            self.assertEqual(results[0], results[1])
            self.assertEqual(results[0][1], "source v1")
            self.assertEqual(counter.read_text().splitlines(), ["build"])
        finally:
            for worker in workers:
                if worker.is_alive():
                    worker.terminate()
                    worker.join()
            result_queue.close()

    def test_waiting_process_rechecks_inputs_after_acquiring_lock(self):
        identity = IDENTITY
        key = cache.content_key(cache.package_inputs(self.repo), identity)
        locks = self.store / "deps-graph/locks"
        locks.mkdir(parents=True)
        # An exec'ed worker does not inherit this lock fd. Its initial identity is
        # frozen only for this test, so source mutation is the one changed input.
        worker_code = '''import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("helper", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
repo = pathlib.Path(sys.argv[2]); store = pathlib.Path(sys.argv[3])
def builder(snapshot, scratch, identity):
    scratch.mkdir(); binary = scratch / "deps-graph"
    binary.write_bytes((snapshot / "Sources/deps-graph/main.swift").read_bytes())
    binary.chmod(0o755); return binary
print(m.ensure_deps_graph(repo, store, identity_provider=lambda: %s, builder=builder))
''' % repr(identity)
        with cache.key_lock(locks / (key + ".lock")):
            process = subprocess.Popen(
                [sys.executable, "-c", worker_code, str(SCRIPT), str(self.repo), str(self.store)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            # Wait for the explicit lock-wait boundary instead of a guessed sleep.
            line = process.stderr.readline()
            self.assertIn("waiting for builder", line)
            self.source.write_text("source changed while waiting")
        stdout, stderr = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 0, stderr)
        self.assertEqual(Path(stdout.strip()).read_text(), "source changed while waiting")
        self.assertFalse((self.store / "deps-graph/entries" / key).exists())

    def test_symlinked_entry_is_rejected_without_touching_target(self):
        binary = self.ensure()
        original_entry = binary.parent
        moved = self.root / "external"
        original_entry.rename(moved)
        original_entry.symlink_to(moved, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, "symlinked cache entry"):
            self.ensure()
        self.assertEqual((moved / "deps-graph").read_text(), "source v1")


if __name__ == "__main__":
    unittest.main()
