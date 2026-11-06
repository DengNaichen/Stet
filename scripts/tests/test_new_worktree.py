"""Exercise creation against local Git remotes; never touch the user's worktrees."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "new-worktree"


class NewWorktreeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / "primary checkout"
        self.remote = self.root / "origin.git"
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1", GIT_TERMINAL_PROMPT="0")
        self.run_command("git", "init", "--bare", str(self.remote))
        self.run_command("git", "init", "-b", "main", str(self.repo))
        self.git("config", "user.name", "Worktree Test")
        self.git("config", "user.email", "worktree@example.invalid")
        (self.repo / "scripts").mkdir()
        shutil.copy2(SOURCE, self.repo / "scripts/new-worktree")
        setup = self.repo / "scripts/setup-worktree"
        setup.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$SETUP_LOG"\nexit "${SETUP_EXIT:-0}"\n')
        setup.chmod(0o755)
        self.env["SETUP_LOG"] = str(self.root / "setup.log")
        (self.repo / "README.md").write_text("baseline\n")
        self.git("add", "scripts", "README.md")
        self.git("commit", "-m", "baseline")
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "-u", "origin", "main")

    def run_command(self, *args, cwd=None, check=True):
        return subprocess.run(args, cwd=cwd or self.root, env=self.env,
                              capture_output=True, text=True, check=check)

    def git(self, *args):
        return self.run_command("git", *args, cwd=self.repo).stdout.strip()

    def create(self, *args):
        return self.run_command("/bin/sh", str(self.repo / "scripts/new-worktree"),
                                *args, cwd=self.repo, check=False)

    def test_creates_from_fresh_main_without_tracking_main(self):
        # Advance the server while the checkout's origin/main remains stale.
        old = self.git("rev-parse", "origin/main")
        (self.repo / "fresh.txt").write_text("new baseline\n")
        self.git("add", "fresh.txt")
        self.git("commit", "-m", "new main")
        self.git("push", "origin", "main")
        self.git("update-ref", "refs/remotes/origin/main", old)
        (self.repo / "README.md").write_text("uncommitted work\n")
        result = self.create("issue-42-example")
        self.assertEqual(result.returncode, 0, result.stderr)
        target = Path(result.stdout.strip())
        self.assertEqual(target, self.root / "stet-worktrees/issue-42-example")
        self.assertEqual((target / "fresh.txt").read_text(), "new baseline\n")
        self.assertEqual((self.repo / "README.md").read_text(), "uncommitted work\n")
        upstream = self.run_command("git", "config", "--get", "branch.issue-42-example.merge",
                                    cwd=self.repo, check=False)
        self.assertNotEqual(upstream.returncode, 0)
        self.assertTrue((self.root / "setup.log").exists())

    def test_resume_reuses_worktree_and_preserves_dirty_files(self):
        first = self.create("fix/example")
        self.assertEqual(first.returncode, 0, first.stderr)
        target = Path(first.stdout.strip())
        (target / "scratch.txt").write_text("keep\n")
        second = self.create("fix/example")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(first.stdout, second.stdout)
        self.assertEqual((target / "scratch.txt").read_text(), "keep\n")
        self.assertIn("--if-needed", (self.root / "setup.log").read_text())
        self.assertNotEqual(self.create("fix/example", "--base", "origin/main").returncode, 0)

    def test_fetch_failure_does_not_use_cached_base(self):
        self.git("remote", "set-url", "origin", str(self.root / "missing.git"))
        result = self.create("fix/offline")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("branch", "--list", "fix/offline"), "")

    def test_setup_failure_preserves_worktree_for_retry(self):
        self.env["SETUP_EXIT"] = "7"
        result = self.create("fix/setup")
        self.assertNotEqual(result.returncode, 0)
        target = self.root / "stet-worktrees/fix-setup"
        self.assertTrue(target.is_dir())
        self.assertNotEqual(self.git("branch", "--list", "fix/setup"), "")
        self.env["SETUP_EXIT"] = "0"
        self.assertEqual(self.create("fix/setup").returncode, 0)

    def test_local_stack_and_no_setup(self):
        self.git("branch", "issue-41-base")
        result = self.create("issue-42-on-41", "--base", "issue-41-base", "--no-setup")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "setup.log").exists())

    def test_path_collision_does_not_overwrite_existing_directory(self):
        self.assertEqual(self.create("fix/example").returncode, 0)
        result = self.create("fix-example")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("branch", "--list", "fix-example"), "")


if __name__ == "__main__":
    unittest.main()
