import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "ci_source_mtimes", Path(__file__).resolve().parents[1] / "ci-source-mtimes.py"
)
mtimes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mtimes)


class SourceMtimeTests(unittest.TestCase):
    def test_only_identical_tracked_inputs_restore_nanosecond_timestamps(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            source = root / "Sources"
            source.mkdir()
            original = 1_700_000_000_123_456_789
            fresh = original + 10_000_000_000
            for name in ("same.swift", "edited.swift", "deleted.swift"):
                (source / name).write_text("original")
                os.utime(source / name, ns=(original, original))
            (source / "alias.swift").symlink_to("same.swift")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            manifest = root / "cache.json"
            mtimes.save(root, manifest)
            self.assertNotIn("Sources/alias.swift", json.loads(manifest.read_text()))
            # Simulate a checkout and a same-length edit, including its mtime.
            (source / "edited.swift").write_text("modified")
            (source / "deleted.swift").unlink()
            (source / "new.swift").write_text("new")
            for path in (source / "same.swift", source / "edited.swift", source / "new.swift", source):
                os.utime(path, ns=(fresh, fresh))
            mtimes.restore(root, manifest)
            self.assertEqual((source / "same.swift").stat().st_mtime_ns, original)
            self.assertEqual((source / "edited.swift").stat().st_mtime_ns, fresh)
            self.assertEqual((source / "new.swift").stat().st_mtime_ns, fresh)
            self.assertEqual(source.stat().st_mtime_ns, fresh)
            self.assertFalse((source / "deleted.swift").exists())

    def test_missing_cache_and_untracked_cache_entries_do_not_modify_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            manifest = root / "cache.json"
            mtimes.restore(root, manifest)
            source = root / "untracked.swift"
            source.write_text("same")
            timestamp = source.stat().st_mtime_ns
            manifest.write_text(json.dumps({
                "untracked.swift": {"sha256": mtimes.fingerprint(source), "mtime_ns": 1},
                "../outside.swift": {"sha256": mtimes.fingerprint(source), "mtime_ns": 1},
            }))
            mtimes.restore(root, manifest)
            self.assertEqual(source.stat().st_mtime_ns, timestamp)

    def test_resource_edit_invalidates_directory_without_changing_membership(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            assets = root / "Assets.xcassets"
            assets.mkdir()
            resource = assets / "Contents.json"
            resource.write_text('{"version":1}')
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            manifest = root / "cache.json"
            mtimes.save(root, manifest)
            resource.write_text('{"version":2}')
            fresh = assets.stat().st_mtime_ns + 10_000_000_000
            os.utime(assets, ns=(fresh, fresh))
            os.utime(resource, ns=(fresh, fresh))
            mtimes.restore(root, manifest)
            self.assertEqual(assets.stat().st_mtime_ns, fresh)
            self.assertEqual(resource.stat().st_mtime_ns, fresh)

    def test_corrupt_timestamp_metadata_falls_back_to_fresh_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            source = root / "main.swift"
            source.write_text("source")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            timestamp = source.stat().st_mtime_ns
            manifest = root / "cache.json"
            for contents in ("not JSON", "[]", '{"main.swift": {"mtime_ns": "invalid"}}'):
                manifest.write_text(contents)
                mtimes.restore(root, manifest)
                self.assertEqual(source.stat().st_mtime_ns, timestamp)
