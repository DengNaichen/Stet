"""Exercise host setup and commit-hook boundaries with isolated repositories/tools."""
from pathlib import Path
import configparser
import json
import os
import shutil
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
GIT = shutil.which("git")


def executable(path, body):
    path.write_text(f"#!{sys.executable}\n" + body)
    path.chmod(0o755)


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="stet-setup-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.scripts = self.root / "scripts"
        self.scripts.mkdir()
        (self.root / "Stet.xcodeproj").mkdir()
        for name in ("setup-worktree", "setup-worktree.py", "run-agent-hook"):
            shutil.copy2(ROOT / "scripts" / name, self.scripts / name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.bin / "python3").symlink_to(sys.executable)
        # setup's shell entrypoint uses dirname before its PATH bootstrap.
        (self.bin / "dirname").symlink_to(shutil.which("dirname"))
        for name in ("swift", "xcodebuild"):
            executable(self.bin / name, f"print('fixture {name} version')\n")
        executable(self.bin / "xcrun", """
import os, pathlib, sys
if os.environ.get('FAIL_XCRUN'):
    sys.exit(31)
print(pathlib.Path(__file__).parent / sys.argv[-1])
""")
        executable(self.scripts / "worktree-cache.py", """
from pathlib import Path
import os, sys
root = Path(__file__).resolve().parent.parent
with (root / 'cache-calls').open('a') as log:
    log.write(' '.join(sys.argv[1:]) + '\\n')
if os.environ.get('FAIL_CACHE'):
    print('fixture cache builder failed', file=sys.stderr)
    sys.exit(32)
binary = root / 'cached-deps-graph'
if not binary.exists():
    (root / 'build-count').write_text('1')
    binary.write_text('#!/bin/sh\\nexit 0\\n')
    binary.chmod(0o755)
print(binary)
""")
        self.env = {**os.environ, "PATH": str(self.bin), "HOME": str(self.root)}

    def run_setup(self, *args, extra=None):
        return subprocess.run(
            [str(self.scripts / "setup-worktree"), *args], cwd="/tmp",
            env={**self.env, **(extra or {})}, capture_output=True, text=True,
        )

    def test_repeated_if_needed_revalidates_but_reuses_prepared_tool(self):
        first = self.run_setup()
        second = self.run_setup("--if-needed")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual((self.root / "cache-calls").read_text().splitlines(), ["deps-graph"] * 2)
        self.assertEqual((self.root / "build-count").read_text(), "1")
        self.assertEqual(second.stdout, "")
        self.assertIn(str(self.root), second.stderr)
        self.assertIn("app builds are not ready", second.stderr)
        self.assertIn("build-xcframework.sh", second.stderr)
        self.assertIn("app build not run", second.stderr)
        self.assertNotIn("make build", (self.root / "cache-calls").read_text())

    def test_present_runtime_is_reported_without_modification(self):
        runtime = self.root / "Packages/StetEngine/Vendor/FunASRPackage/Artifacts/FunASRRuntime.xcframework"
        runtime.mkdir(parents=True)
        marker = runtime / "original"
        marker.write_text("keep")
        result = self.run_setup("--if-needed")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("WARNING", result.stderr)
        self.assertEqual(marker.read_text(), "keep")

    def test_selected_toolchain_failure_stops_before_cache(self):
        result = self.run_setup(extra={"FAIL_XCRUN": "1"})
        self.assertEqual(result.returncode, 31)
        self.assertFalse((self.root / "cache-calls").exists())

    def test_cache_failure_is_not_reported_as_ready(self):
        result = self.run_setup(extra={"FAIL_CACHE": "1"})
        self.assertEqual(result.returncode, 32)
        self.assertIn("fixture cache builder failed", result.stderr)
        self.assertNotIn("architecture tool ready", result.stderr)

    def test_unknown_argument_is_rejected(self):
        result = self.run_setup("--force-unrelated")
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.root / "cache-calls").exists())


class PreCommitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="stet-hook-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        subprocess.run([GIT, "init", "-q", str(self.repo)], check=True)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.bin / "git").symlink_to(GIT)
        (self.bin / "python3").symlink_to(sys.executable)
        self.log = self.root / "commands.jsonl"
        executable(self.bin / "make", """
import json, os, pathlib, sys
with open(os.environ['HOOK_LOG'], 'a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\\n')
if sys.argv[1] == 'format':
    for name in json.loads(os.environ.get('FORMAT_FILES', '[]')):
        pathlib.Path(name).write_text('formatted\\n')
if os.environ.get('FAIL_MAKE') == sys.argv[1]:
    sys.exit(23)
""")
        self.env = {**os.environ, "PATH": str(self.bin), "HOOK_LOG": str(self.log)}

    def stage(self, name, content="original\n"):
        (self.repo / name).write_text(content)
        subprocess.run([GIT, "-C", str(self.repo), "add", "--", name], check=True)

    def run_hook(self, extra=None, cwd=None):
        return subprocess.run(
            ["/bin/sh", str(ROOT / ".githooks/pre-commit")], cwd=cwd or self.repo,
            env={**self.env, **(extra or {})}, capture_output=True, text=True,
        )

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_no_rg_still_formats_and_lints_swift(self):
        self.stage("Thing.swift")
        self.assertIsNone(shutil.which("rg", path=self.env["PATH"]))
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.commands(), [["format"], ["swiftlint"]])

    def test_no_staged_swift_skips_checks(self):
        self.stage("README.md")
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.commands(), [])

    def test_spaces_and_newlines_survive_and_only_staged_swift_is_added(self):
        name = "Audio input\npanel.swift"
        self.stage(name)
        (self.repo / "Unstaged.swift").write_text("original\n")
        result = self.run_hook({"FORMAT_FILES": json.dumps([name, "Unstaged.swift"])})
        self.assertEqual(result.returncode, 0, result.stderr)
        staged = subprocess.check_output([GIT, "-C", str(self.repo), "diff", "--cached", "--name-only", "-z"])
        self.assertEqual(staged.split(b"\0"), [os.fsencode(name), b""])
        stored = subprocess.check_output([GIT, "-C", str(self.repo), "show", ":" + name])
        self.assertEqual(stored, b"formatted\n")

    def test_format_failure_stops_before_restaging_or_lint(self):
        self.stage("Thing.swift")
        result = self.run_hook({"FAIL_MAKE": "format", "FORMAT_FILES": '["Thing.swift"]'})
        self.assertEqual(result.returncode, 23)
        self.assertEqual(self.commands(), [["format"]])
        stored = subprocess.check_output([GIT, "-C", str(self.repo), "show", ":Thing.swift"])
        self.assertEqual(stored, b"original\n")

    def test_lint_failure_fails_hook(self):
        self.stage("Thing.swift")
        result = self.run_hook({"FAIL_MAKE": "swiftlint"})
        self.assertEqual(result.returncode, 23)
        self.assertEqual(self.commands(), [["format"], ["swiftlint"]])

    def test_git_discovery_failure_does_not_silently_skip(self):
        result = self.run_hook(cwd=self.root)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.commands(), [])

    def test_git_diff_failure_does_not_silently_skip(self):
        (self.bin / "git").unlink()
        executable(self.bin / "git", f"""
import os, sys
if sys.argv[1] == 'diff':
    sys.exit(42)
os.execv({GIT!r}, [{GIT!r}, *sys.argv[1:]])
""")
        result = self.run_hook()
        self.assertEqual(result.returncode, 42)
        self.assertEqual(self.commands(), [])


class AdapterRoutingTests(unittest.TestCase):
    """Execute configured commands, without claiming desktop GUI hook delivery."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="stet-adapter-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.primary = self.make_checkout("primary checkout")
        self.target = self.make_checkout("target checkout")
        self.nested = self.target / "nested directory"
        self.nested.mkdir()
        self.env = {**os.environ, "CLAUDE_PROJECT_DIR": str(self.primary)}

    def make_checkout(self, name):
        repo = self.root / name
        repo.mkdir()
        subprocess.run([GIT, "init", "-q", str(repo)], check=True)
        scripts = repo / "scripts"
        scripts.mkdir()
        shutil.copy2(ROOT / "scripts/run-agent-hook", scripts / "run-agent-hook")
        executable(scripts / "setup-worktree", """
from pathlib import Path
import json, os, sys
root = Path(__file__).resolve().parent.parent
(root / 'setup-record.json').write_text(json.dumps({
    'root': str(root), 'cwd': str(Path.cwd()), 'arguments': sys.argv[1:]
}))
sys.exit(int(os.environ.get('STET_FIXTURE_SETUP_EXIT', '0')))
""")
        return repo

    def session_commands(self):
        for name in (".claude/settings.json", ".codex/hooks.json"):
            config = json.loads((ROOT / name).read_text())
            groups = config["hooks"]["SessionStart"]
            self.assertEqual(len(groups), 1)
            self.assertEqual(groups[0]["matcher"], "startup|resume")
            hooks = groups[0]["hooks"]
            self.assertEqual(len(hooks), 1)
            self.assertEqual(hooks[0]["type"], "command")
            yield name, hooks[0]["command"]

    def assert_target_prepared(self, arguments):
        self.assertFalse((self.primary / "setup-record.json").exists())
        record = json.loads((self.target / "setup-record.json").read_text())
        self.assertEqual(record["root"], str(self.target.resolve()))
        self.assertEqual(record["arguments"], arguments)
        return record

    def test_session_commands_use_current_checkout_not_stale_claude_project_dir(self):
        for name, command in self.session_commands():
            with self.subTest(adapter=name):
                result = subprocess.run(
                    ["/bin/sh", "-c", command], cwd=self.nested, env=self.env,
                    input=json.dumps({"cwd": str(self.nested)}), capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                record = self.assert_target_prepared(["--if-needed"])
                self.assertEqual(record["cwd"], str(self.nested.resolve()))

    def test_session_adapters_propagate_setup_failure(self):
        for name, command in self.session_commands():
            with self.subTest(adapter=name):
                result = subprocess.run(
                    ["/bin/sh", "-c", command], cwd=self.nested,
                    env={**self.env, "STET_FIXTURE_SETUP_EXIT": "37"},
                    capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 37, result.stderr)
                self.assert_target_prepared(["--if-needed"])

    def test_session_outside_git_does_not_modify_primary_checkout(self):
        for name, command in self.session_commands():
            with self.subTest(adapter=name):
                result = subprocess.run(
                    ["/bin/sh", "-c", command], cwd=self.root, env=self.env,
                    capture_output=True, text=True,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.primary / "setup-record.json").exists())
                self.assertFalse((self.target / "setup-record.json").exists())

    def test_codex_darwin_environment_runs_setup_from_target_checkout(self):
        # This file uses only the flat, INI-compatible subset of TOML. Read its
        # quoted script values without adding tomllib (unavailable in Python 3.9).
        config = configparser.ConfigParser(interpolation=None)
        config.read_string("[root]\n" + (ROOT / ".codex/environments/environment.toml").read_text())
        self.assertEqual(config["root"]["version"], "1")
        self.assertEqual(json.loads(config["setup"]["script"]), "")
        command = json.loads(config["setup.darwin"]["script"])
        result = subprocess.run(
            ["/bin/sh", "-c", command], cwd=self.target, env=self.env,
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_target_prepared(["--if-needed"])

    def test_cursor_string_command_resolves_relative_to_its_config_directory(self):
        config_dir = self.target / ".cursor"
        config_dir.mkdir()
        shutil.copy2(ROOT / ".cursor/worktrees.json", config_dir / "worktrees.json")
        config = json.loads((config_dir / "worktrees.json").read_text())
        command = config["setup-worktree-unix"]
        self.assertIsInstance(command, str)
        arguments = shlex.split(command)
        # Cursor resolves a string entry relative to the configuration file.
        executable_path = (config_dir / arguments[0]).resolve()
        self.assertEqual(executable_path, (self.target / "scripts/setup-worktree").resolve())
        result = subprocess.run(
            [str(executable_path), *arguments[1:]], cwd=self.target, env=self.env,
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_target_prepared(arguments[1:])


if __name__ == "__main__":
    unittest.main()
