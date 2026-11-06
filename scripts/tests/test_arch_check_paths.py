"""Worktree aliases must not turn valid source files into unknown-layer files."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "arch-check.py"
spec = importlib.util.spec_from_file_location("arch_check_path_tests", SCRIPT)
arch = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = arch
spec.loader.exec_module(arch)


class ArchitecturePathTests(unittest.TestCase):
    def read_facts(self, root, file):
        facts = {
            "decls": [{"file": file, "name": "Thing"}],
            "refs": [{"file": file, "from": "Thing", "to": "Other"}],
            "imports": [{"file": file, "module": "Foundation"}],
        }
        answers = [
            subprocess.CompletedProcess([], 0, stdout="/cache/deps-graph\n"),
            subprocess.CompletedProcess([], 0, stdout=json.dumps(facts)),
        ]
        with patch.object(arch, "ROOT", root), patch.object(arch, "SRC", root / "StetMac"):
            with patch.object(arch.subprocess, "run", side_effect=answers):
                return arch.load_facts()

    def test_absolute_alias_paths_become_repo_relative_for_all_fact_types(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / "real worktree"
            source = root / "StetMac/Core/Thing.swift"
            source.parent.mkdir(parents=True)
            source.write_text("struct Thing {}")
            alias = base / "worktree alias"
            alias.symlink_to(root, target_is_directory=True)
            facts = self.read_facts(root, str(alias / "StetMac/Core/Thing.swift"))
            for records in facts.values():
                self.assertEqual(records[0]["file"], "StetMac/Core/Thing.swift")

    def test_existing_relative_paths_remain_valid(self):
        with tempfile.TemporaryDirectory() as temporary:
            facts = self.read_facts(Path(temporary), "StetMac/Core/Thing.swift")
            self.assertEqual(facts["decls"][0]["file"], "StetMac/Core/Thing.swift")

    def test_paths_outside_checkout_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            with self.assertRaisesRegex(RuntimeError, "outside"):
                self.read_facts(root, str(Path(temporary) / "other/Thing.swift"))


if __name__ == "__main__":
    unittest.main()
