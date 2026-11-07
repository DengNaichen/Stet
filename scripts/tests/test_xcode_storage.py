"""Run the cache cleaner against temporary caches and controlled OS process snapshots."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("zsh"), "requires zsh")
class CacheProcessScopeTests(unittest.TestCase):
    def run_cleanup(self, mode):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "checkout"
            scripts = root / "scripts"
            scripts.mkdir(parents=True)
            (root / "Stet.xcodeproj").mkdir()
            cache = root / ".derivedData"
            cache.mkdir()
            marker = cache / "build.db"
            marker.write_text("cache")
            other = Path(directory) / "checkout-other"
            other.mkdir()
            other_marker = other / "keep"
            other_marker.write_text("unrelated")
            tool = Path(directory) / "system-probe"
            tool.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
snapshot = json.loads(os.environ["STET_TEST_PROCESS_SNAPSHOT"])
name = Path(sys.argv[0]).name
if name == "pgrep":
    sys.exit(0 if "sourcekit-lsp" in sys.argv else 1)
if name == "ps":
    print(snapshot["ps"])
    sys.exit(snapshot.get("ps_status", 0))
if name == "lsof":
    print(snapshot["lsof"])
    sys.exit(snapshot.get("lsof_status", 0))
''')
            tool.chmod(0o755)
            for name in ("pgrep", "ps", "lsof"):
                (Path(directory) / name).symlink_to(tool)
            for name in ("xcode-storage.sh", "check-build-cache-usage.py"):
                source = ROOT / "scripts" / name
                if not source.exists():
                    continue
                text = source.read_text()
                for executable in ("/usr/bin/pgrep", "/bin/ps", "/usr/sbin/lsof"):
                    text = text.replace(executable, str(Path(directory) / Path(executable).name))
                (scripts / name).write_text(text)
            snapshot = {"ps": "123 1 /tool/sourcekit-lsp", "lsof": f"p123\nfcwd\nn{other}"}
            if mode == "target-cwd":
                snapshot["lsof"] = f"p123\nfcwd\nn{root}"
            elif mode == "target-file":
                snapshot["lsof"] += f"\nf5\nn{marker}"
            elif mode == "target-command":
                snapshot["ps"] += f" --project {root}/Stet.xcodeproj"
            elif mode == "unknown":
                snapshot["lsof"] = ""
                snapshot["lsof_status"] = 1
            elif mode == "ps-failure":
                snapshot["ps_status"] = 1
            elif mode == "no-cache":
                marker.unlink()
                cache.rmdir()
            result = subprocess.run(
                ["zsh", str(scripts / "xcode-storage.sh"), "clean-project"],
                env={**os.environ, "STET_TEST_PROCESS_SNAPSHOT": json.dumps(snapshot)},
                capture_output=True, text=True,
            )
            self.assertEqual(other_marker.read_text(), "unrelated")
            return result, marker.exists()

    def test_other_checkout_indexer_does_not_block_cleanup(self):
        result, exists = self.run_cleanup("unrelated")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(exists)

    def test_no_cache_is_a_successful_noop_with_other_checkout_indexer(self):
        result, _ = self.run_cleanup("no-cache")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_target_processes_and_unknown_state_preserve_cache(self):
        for mode in ("target-cwd", "target-file", "target-command", "unknown", "ps-failure"):
            with self.subTest(mode=mode):
                result, exists = self.run_cleanup(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(exists)
