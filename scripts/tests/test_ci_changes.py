import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/ci-changes.py"
spec = importlib.util.spec_from_file_location("ci_changes", SCRIPT)
changes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(changes)


class RoutingTests(unittest.TestCase):
    def test_lightweight_changes_do_not_allocate_macos(self):
        for path in (
            changes.COMPATIBILITY, "docs/specs/app-compatibility.md", "README.md",
            "reference/apple-platform/index.md", ".github/README.md", "AGENTS.md",
            "scripts/validate-app-compatibility.py", "scripts/validate-agent-entrypoints",
        ):
            with self.subTest(path=path):
                self.assertEqual(changes.classify([path]), dict(quality=False, macos=False, workflows=False))

    def test_runtime_inputs_and_unknown_paths_keep_build_and_test_coverage(self):
        for path in (
            "StetMac/Core/Service.swift", "StetMacTests/Example.swift",
            "StetVisuals/Shader.metal", "StetMac/Resources/asset.png",
            "StetMac/Resources/prompt.md", "StetMac/Stet.entitlements",
            "Packages/StetEngine/Package.swift", "Packages/StetEngine/Sources/Engine.swift",
            "Packages/StetEngine/Vendor/FunASRPackage/RuntimeSource/stet_funasr.cpp",
            "Stet.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            "Stet.xcodeproj/xcshareddata/xcschemes/Stet.xcscheme", "Info.plist",
            "scripts/normalize-binary-frameworks.sh", "scripts/ci-source-mtimes.py",
            "NewModule/input.xyz",
        ):
            with self.subTest(path=path):
                self.assertTrue(changes.classify([path])["macos"])

    def test_ios_changes_do_not_build_macos(self):
        for path in ("StetMobile/StetMobile/App.swift", "StetMobile/StetKeyboard/Keyboard.swift"):
            self.assertEqual(changes.classify([path]), dict(quality=True, macos=False, workflows=False))
        self.assertFalse(changes.classify(["StetMobile/StetMobile/Assets.xcassets/Contents.json"])["quality"])

    def test_ci_routing_changes_exercise_full_pipeline(self):
        for path in changes.FULL_CI:
            self.assertEqual(changes.classify([path]), dict(quality=True, macos=True, workflows=True))
        self.assertEqual(
            changes.classify([".github/workflows/macos-release.yml"]),
            dict(quality=False, macos=False, workflows=True),
        )

    def test_lint_configs_and_mixed_changes(self):
        self.assertEqual(changes.classify([".swift-format"]), dict(quality=True, macos=False, workflows=False))
        self.assertTrue(changes.classify([changes.COMPATIBILITY, "StetMac/App.swift"])["macos"])
        self.assertTrue(changes.classify(["README.md", "StetMobile/StetMobile/App.swift"])["quality"])


class GitDiffTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "CI Test")
        self.git("config", "user.email", "ci-test@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.write("README.md", "initial")
        self.base = self.commit()

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, stderr=subprocess.PIPE).decode().strip()

    def write(self, path, content="changed"):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content)

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")
        return self.git("rev-parse", "HEAD")

    def run_plan(self, event_name, event, success=True):
        # Keep event/output files outside the fixture's Git tree.
        with tempfile.TemporaryDirectory() as io_dir:
            event_path = Path(io_dir) / "event.json"
            event_path.write_text(json.dumps(event))
            output = Path(io_dir) / "output"
            env = {**os.environ, "GITHUB_OUTPUT": str(output), "GITHUB_STEP_SUMMARY": str(Path(io_dir) / "summary")}
            result = subprocess.run(
                ["python3", str(SCRIPT), "--event-name", event_name, "--event-path", str(event_path)],
                cwd=self.root, env=env, text=True, capture_output=True,
            )
            if not success:
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())
                return
            self.assertEqual(result.returncode, 0, result.stderr)
            value = json.loads(result.stdout)
            for name in ("quality", "macos", "workflows"):
                self.assertIn(f"{name}={str(value[name]).lower()}\n", output.read_text())
            return value

    def test_pr_considers_all_commits_but_not_unrelated_base_changes(self):
        self.git("checkout", "-qb", "feature")
        self.write(changes.COMPATIBILITY)
        self.commit()
        self.write("docs/new.md")
        head = self.commit()
        self.git("checkout", "-q", "main")
        self.write("StetMac/unrelated.swift")
        current_base = self.commit()
        self.git("merge", "--no-ff", "feature", "-m", "simulated PR checkout")
        value = self.run_plan("pull_request", {"pull_request": {"base": {"sha": current_base}, "head": {"sha": head}}})
        self.assertEqual(set(value["paths"]), {changes.COMPATIBILITY, "docs/new.md"})
        self.assertEqual(value["base_ref"], current_base)
        self.assertFalse(value["macos"])

    def test_push_covers_every_commit_not_only_head_parent(self):
        self.write("StetMac/App.swift")
        self.commit()
        self.write("docs/new.md")
        head = self.commit()
        value = self.run_plan("push", {"before": self.base, "after": head})
        self.assertTrue(value["macos"])
        self.assertTrue(value["quality"])

    def test_multi_commit_push_cannot_hide_missing_compatibility_revision_bump(self):
        config = dict(schemaVersion=1, revision=1, bundleIDs=["com.example.one"])
        self.write(changes.COMPATIBILITY, json.dumps(config))
        base = self.commit()
        config["bundleIDs"].append("com.example.two")
        self.write(changes.COMPATIBILITY, json.dumps(config))
        self.commit()
        self.write("docs/last-commit.md")
        head = self.commit()
        value = self.run_plan("push", {"before": base, "after": head})
        result = subprocess.run(
            ["python3", str(ROOT / "scripts/validate-app-compatibility.py"), "--base-ref", value["base_ref"]],
            cwd=self.root, text=True, capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Increment revision", result.stderr)

    def test_renamed_and_deleted_sources_still_trigger_tests(self):
        self.write("StetMac/App.swift")
        self.write("StetVisuals/old.metal")
        base = self.commit()
        self.git("mv", "StetMac/App.swift", "renamed.md")
        self.git("rm", "StetVisuals/old.metal")
        head = self.commit()
        value = self.run_plan("push", {"before": base, "after": head})
        self.assertEqual(set(value["paths"]), {"StetMac/App.swift", "renamed.md", "StetVisuals/old.metal"})
        self.assertTrue(value["macos"])
        self.assertTrue(value["quality"])

    def test_large_diff_and_unusual_filenames(self):
        for index in range(350):
            self.write(f"docs/{index}.md")
        self.write("StetMac/a file\nwith newline.swift")
        head = self.commit()
        value = self.run_plan("push", {"before": self.base, "after": head})
        self.assertEqual(len(value["paths"]), 351)
        self.assertIn("StetMac/a file\nwith newline.swift", value["paths"])
        self.assertTrue(value["macos"])

    def test_new_branch_and_empty_diff(self):
        self.write("StetMac/App.swift")
        head = self.commit()
        value = self.run_plan("push", {"before": "0" * 40, "after": head})
        self.assertTrue(value["macos"])
        self.assertEqual(value["base_ref"], "")
        value = self.run_plan("push", {"before": head, "after": head})
        self.assertEqual(value["paths"], [])
        self.assertFalse(value["macos"])

    def test_missing_diff_ref_fails_instead_of_skipping_checks(self):
        self.run_plan("push", {"before": "f" * 40, "after": self.base}, success=False)
        self.run_plan("unknown", {}, success=False)


class ResultGateTests(unittest.TestCase):
    def test_actual_workflow_gate_rejects_failed_cancelled_or_missing_checks(self):
        # Execute the workflow's real gate rather than a duplicate implementation.
        workflow = (ROOT / ".github/workflows/monorepo-ci.yml").read_text()
        code = textwrap.dedent(workflow.split("python3 - <<'PY'\n")[1].split("          PY")[0])
        for plan_result, selected, job_result, passed in (
            ("success", "true", "success", True),
            ("success", "false", "skipped", True),
            ("success", "true", "failure", False),
            ("success", "true", "cancelled", False),
            ("success", "true", "skipped", False),
            ("success", "", "skipped", False),
            ("failure", "false", "skipped", False),
            ("cancelled", "false", "skipped", False),
        ):
            with self.subTest(plan_result=plan_result, selected=selected, job_result=job_result):
                needs = {
                    "changes": {"result": plan_result, "outputs": {"quality": selected, "macos": selected}},
                    "quality": {"result": job_result}, "macos": {"result": job_result},
                }
                result = subprocess.run(
                    ["python3", "-c", code], capture_output=True,
                    env={**os.environ, "NEEDS_JSON": json.dumps(needs)},
                )
                self.assertEqual(result.returncode == 0, passed, result.stderr)


if __name__ == "__main__":
    unittest.main()
