"""Exercise discovery and exit codes through the real offline CLI."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'lint.py'


class CLITest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        (self.root / 'linter').mkdir()
        (self.root / 'linter/config.toml').write_text('[markdown]\nexclude = ["reference/**"]\n')

    def run_lint(self, root=None):
        return subprocess.run([sys.executable, '-B', str(SCRIPT), '--root', str(root or self.root)],
                              text=True, capture_output=True)

    def test_untracked_markdown_and_excluded_reference(self):
        (self.root / 'reference').mkdir()
        (self.root / 'reference/old.md').write_text('[broken](absent.md)')
        (self.root / 'README.md').write_text('[ref](reference/old.md#historical)')
        result = self.run_lint()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('fragments_skipped_excluded=1', result.stdout)
        (self.root / 'new.md').write_text('[broken](absent.md)')
        result = self.run_lint(self.root / 'linter')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('new.md:1: MD_TARGET', result.stdout)

    def test_deleted_target_and_source_alias(self):
        (self.root / 'README.md').write_text('[target](target.md#okay)')
        (self.root / 'target.md').write_text('# Okay')
        (self.root / 'CLAUDE.md').symlink_to('README.md')
        subprocess.run(['git', '-C', str(self.root), 'add', '.'], check=True)
        result = self.run_lint()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('documents_checked=2', result.stdout)
        (self.root / 'target.md').unlink()
        result = self.run_lint()
        self.assertEqual(result.returncode, 1)
        self.assertIn('README.md:1: MD_TARGET', result.stdout)

    def test_invalid_config_fails_as_setup_error(self):
        (self.root / 'linter/config.toml').write_text('[markdown]\nexclude = "bad"\n')
        result = self.run_lint()
        self.assertEqual(result.returncode, 2)
        self.assertIn('setup error', result.stderr)
