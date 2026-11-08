import hashlib
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "prefetch", Path(__file__).parents[1] / "prefetch-release-binaries.py"
)
prefetch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prefetch)

URL = "https://github.com/owner/repo/releases/download/v1.0/archive.zip"


class PrefetchTests(unittest.TestCase):
    def test_range_download_reassembles_exact_bytes(self):
        payload = b"a" * (16 * 1024 * 1024) + b"tail"
        ranges = []

        def curl(command, **kwargs):
            byte_range = command[command.index("--range") + 1]
            ranges.append(byte_range)
            start, end = map(int, byte_range.split("-"))
            Path(command[command.index("--output") + 1]).write_bytes(payload[start:end + 1])
            return subprocess.CompletedProcess(command, 0, stdout="206")

        with tempfile.TemporaryDirectory() as directory, patch.object(prefetch.subprocess, "run", side_effect=curl):
            archive = Path(directory) / "archive.zip"
            prefetch.download_asset("https://api.github.com/example", len(payload), archive)
            self.assertEqual(archive.read_bytes(), payload)
            self.assertEqual(ranges, ["0-16777215", "16777216-16777219"])

    def test_range_response_must_not_be_truncated_or_ignored(self):
        for status, payload in [("206", b"x"), ("200", b"abc")]:
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                def curl(command, **kwargs):
                    Path(command[command.index("--output") + 1]).write_bytes(payload)
                    return subprocess.CompletedProcess(command, 0, stdout=status)

                with patch.object(prefetch.subprocess, "run", side_effect=curl):
                    with self.assertRaises(ValueError):
                        prefetch.download_asset("https://api.github.com/example", 3, Path(directory) / "archive.zip")

    def test_bad_checksum_does_not_replace_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            destination = cache / prefetch.re.sub(r"[^A-Za-z0-9]", "_", URL)
            destination.write_bytes(b"existing")
            metadata = {"assets": [{"name": "archive.zip", "id": 123, "size": 3}]}
            with patch.object(prefetch, "github_api", return_value=metadata), patch.object(
                prefetch, "download_asset", side_effect=lambda url, size, path: path.write_bytes(b"bad")
            ):
                with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
                    prefetch.prefetch(URL, hashlib.sha256(b"good").hexdigest(), cache)
            self.assertEqual(destination.read_bytes(), b"existing")
            self.assertEqual(list(cache.iterdir()), [destination])

    def test_verified_cache_skips_network(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            destination = cache / prefetch.re.sub(r"[^A-Za-z0-9]", "_", URL)
            destination.write_bytes(b"good")
            with patch.object(prefetch, "github_api") as api:
                self.assertEqual(prefetch.prefetch(URL, hashlib.sha256(b"good").hexdigest(), cache), destination)
                api.assert_not_called()

    def test_manifest_uses_declared_tag_and_checksum(self):
        checksum = "a" * 64
        manifest = f'let tag = "2.9.0"\nlet url = "https://example.com/\\(tag)/archive.zip"\nlet checksum = "{checksum}"'
        self.assertEqual(prefetch.manifest_artifact(manifest), ("https://example.com/2.9.0/archive.zip", checksum))


if __name__ == "__main__":
    unittest.main()
