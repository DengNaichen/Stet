#!/usr/bin/env python3
"""Seed SwiftPM's macOS archive cache via GitHub's official release assets API.

Checksums come from the checked-out Sherpa manifest and the locked Sparkle
revision. SwiftPM still verifies the archives when resolving the packages.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import quote, unquote, urlsplit


def github_api(endpoint, raw=False):
    command = ["gh", "api", endpoint]
    if raw:
        command += ["-H", "Accept: application/vnd.github.raw+json"]
    output = subprocess.check_output(command, text=True)
    return output if raw else json.loads(output)


def manifest_artifact(manifest):
    def field(name):
        match = re.search(rf'\b{name}\s*(?:=|:)\s*"([^"]+)"', manifest)
        if not match:
            raise ValueError(f"Missing literal {name} in binary package manifest")
        return match.group(1)

    url = field("url")
    if r"\(tag)" in url:
        url = url.replace(r"\(tag)", field("tag"))
    checksum = field("checksum")
    if "\\" in url or not re.fullmatch(r"[a-f0-9]{64}", checksum):
        raise ValueError("Unsupported binary package URL or checksum")
    return url, checksum


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_asset(api_url, size, archive):
    # Large full-body responses can reset even while ranged API downloads work.
    # Check every range and the final manifest checksum before exposing the cache.
    chunk_size = 4 * 1024 * 1024
    chunk = archive.with_suffix(".part")
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    # Supply credentials on stdin, never in argv or logs. curl strips this
    # Authorization header when GitHub redirects to the asset storage host.
    config = f'header = "Authorization: Bearer {token}"\n' if token else ""
    with archive.open("wb") as output:
        for start in range(0, size, chunk_size):
            end = min(start + chunk_size, size) - 1
            result = subprocess.run([
                "curl", "--fail", "--silent", "--show-error", "--location",
                "--retry", "3", "--retry-all-errors", "--retry-delay", "2",
                "--connect-timeout", "20", "--max-time", "120",
                "--header", "Accept: application/octet-stream",
                "--range", f"{start}-{end}", "--write-out", "%{http_code}",
                "--config", "-", "--output", str(chunk), api_url,
            ], input=config, capture_output=True, text=True)
            if result.returncode:
                detail = result.stderr.replace(token, "<REDACTED>") if token else result.stderr
                raise RuntimeError(f"Asset range {start}-{end} download failed: {detail.strip()}")
            if result.stdout != "206" or chunk.stat().st_size != end - start + 1:
                raise ValueError(f"Invalid asset range {start}-{end}")
            with chunk.open("rb") as source:
                for block in iter(lambda: source.read(1024 * 1024), b""):
                    output.write(block)


def prefetch(url, checksum, cache):
    parsed = urlsplit(url)
    parts = parsed.path.strip("/").split("/")
    if (parsed.scheme != "https" or parsed.netloc != "github.com"
            or len(parts) != 6 or parts[2:4] != ["releases", "download"]
            or parsed.query or parsed.fragment):
        raise ValueError(f"Unsupported release asset URL: {url}")
    owner, repo, _, _, tag, name = map(unquote, parts)
    # SwiftPM's binary archive cache uses the URL with non-alphanumerics replaced.
    destination = cache / re.sub(r"[^A-Za-z0-9]", "_", url)
    if destination.is_file() and sha256(destination) == checksum:
        print(f"Verified cached {name}", flush=True)
        return destination

    release = github_api(f"repos/{owner}/{repo}/releases/tags/{quote(tag, safe='')}")
    assets = [asset for asset in release["assets"] if asset["name"] == name]
    if len(assets) != 1:
        raise ValueError(f"Expected exactly one release asset named {name}")
    asset_id = int(assets[0]["id"])
    size = int(assets[0]["size"])
    if size <= 0:
        raise ValueError(f"Empty release asset {name}")
    api_url = f"https://api.github.com/repos/{owner}/{repo}/releases/assets/{asset_id}"
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=cache, prefix="stet-download-") as temporary:
        archive = Path(temporary) / "archive.zip"
        print(f"Downloading {owner}/{repo}: {name} via official assets API", flush=True)
        download_asset(api_url, size, archive)
        if sha256(archive) != checksum:
            raise ValueError(f"Checksum mismatch for {name}; cache not modified")
        archive.replace(destination)
    print(f"Verified and cached {name}", flush=True)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--cache-dir", type=Path,
                        default=Path.home() / "Library/Caches/org.swift.swiftpm/artifacts")
    args = parser.parse_args()
    root = args.root
    sherpa = root / "Packages/StetEngine/Vendor/SherpaOnnxPackage/Package.swift"
    lock = json.loads((root / "Stet.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())
    sparkle = next(pin for pin in lock["pins"] if pin["identity"] == "sparkle")
    revision = sparkle["state"]["revision"]
    sparkle_manifest = github_api(
        f"repos/sparkle-project/Sparkle/contents/Package.swift?ref={revision}", raw=True
    )
    for manifest in (sherpa.read_text(), sparkle_manifest):
        prefetch(*manifest_artifact(manifest), args.cache_dir)


if __name__ == "__main__":
    main()
