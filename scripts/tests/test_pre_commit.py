"""Exercise the real commit hook with a PATH that deliberately excludes rg."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


HOOK = Path(__file__).resolve().parents[2] / ".githooks/pre-commit"


class PreCommitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        for command in ("git", "grep", "xargs"):
            executable = shutil.which(command)
            self.assertIsNotNone(executable, command)
            (bin_dir / command).symlink_to(executable)
        make = bin_dir / "make"
        make.write_text(
            '#!/bin/sh\n'
            'echo "$1" >> "$HOOK_TEST_LOG"\n'
            'if [ "$1" = "$HOOK_TEST_FAIL" ]; then exit 1; fi\n'
        )
        make.chmod(0o755)
        self.log = self.root / "calls"
        self.env = {
            **os.environ,
            "PATH": str(bin_dir),
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
            "HOOK_TEST_LOG": str(self.log),
            "HOOK_TEST_FAIL": "",
        }
        self.git("init", "--quiet")
        self.git("config", "user.name", "Hook Test")
        self.git("config", "user.email", "hook-test@example.invalid")
        hooks = self.root / "hooks"
        hooks.mkdir()
        shutil.copyfile(HOOK, hooks / "pre-commit")
        (hooks / "pre-commit").chmod(0o755)
        self.git("config", "core.hooksPath", str(hooks))

    def git(self, *args, check=True):
        return subprocess.run(
            ["git", *args], cwd=self.root, env=self.env,
            capture_output=True, text=True, check=check,
        )

    def commit(self, filename, fail=""):
        (self.root / filename).write_text("// staged fixture\n")
        self.git("add", "--", filename)
        self.env["HOOK_TEST_FAIL"] = fail
        result = self.git("commit", "-m", "fixture", check=False)
        calls = self.log.read_text().splitlines() if self.log.exists() else []
        return result, calls

    def test_swift_commit_runs_checks_without_ripgrep(self):
        result, calls = self.commit("Fixture.swift")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["format", "swiftlint"], result.stderr)

    def test_non_swift_commit_skips_checks(self):
        result, calls = self.commit("README.md")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [])

    def test_lint_failure_blocks_commit(self):
        result, calls = self.commit("Fixture.swift", fail="swiftlint")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, ["format", "swiftlint"])
        self.assertNotEqual(self.git("rev-parse", "--verify", "HEAD", check=False).returncode, 0)

    def test_format_failure_blocks_commit_before_lint(self):
        result, calls = self.commit("Fixture.swift", fail="format")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, ["format"])
        self.assertNotEqual(self.git("rev-parse", "--verify", "HEAD", check=False).returncode, 0)


if __name__ == "__main__":
    unittest.main()
