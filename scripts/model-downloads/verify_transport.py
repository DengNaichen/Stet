#!/usr/bin/env python3
"""Exercise production download sources against a local Range server; --live adds VAD downloads."""
import argparse
import hashlib
import http.server
import json
from pathlib import Path
import subprocess
import tempfile
import threading
import time

REPO = Path(__file__).resolve().parents[2]
PACKAGE = '''// swift-tools-version: 6.1
import PackageDescription
let package = Package(name: "DownloadProbe", platforms: [.macOS(.v14)],
 dependencies: [.package(url: "https://github.com/huggingface/swift-huggingface.git", exact: "1.0.0")],
 targets: [.target(name: "StetCore"), .executableTarget(name: "Probe", dependencies:
 ["StetCore", .product(name: "HuggingFace", package: "swift-huggingface")])])
'''
MAIN = '''import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let url = URL(string: CommandLine.arguments[2])!
let destination = root.appendingPathComponent("model")
let downloader = ModelFileDownloader(cache: root.appendingPathComponent("cache"))
let request = ModelFileRequest(sources: [url], size: Int64(CommandLine.arguments[4])!)
if CommandLine.arguments[3] == "cancel" {
 let task = Task { try await downloader.file(request, at: destination) }
 try await Task.sleep(for: .milliseconds(350)); task.cancel(); _ = await task.result
 precondition(!FileManager.default.fileExists(atPath: destination.path))
}
_ = try await downloader.file(request, at: destination)
_ = try await downloader.file(request, at: destination, localFilesOnly: true)
print("download and local-only cache hit passed")
'''


def build_probe(root):
    (root / 'Sources/Probe').mkdir(parents=True, exist_ok=True)
    (root / 'Sources/StetCore').mkdir(parents=True, exist_ok=True)
    (root / 'Package.swift').write_text(PACKAGE)
    (root / 'Sources/Probe/main.swift').write_text(MAIN)
    files = {
        'Sources/StetCore/ModelDownloadMirror.swift': 'Packages/StetEngine/Sources/StetCore/ModelDownloadMirror.swift',
        'Sources/Probe/ModelFileDownload.swift': 'StetMac/Core/Models/ModelFileDownload.swift',
        'Sources/Probe/ModelFileTransport.swift': 'StetMac/Core/Models/ModelFileTransport.swift',
    }
    for target, source in files.items():
        path = root / target
        if not path.exists():
            path.symlink_to(REPO / source)
    subprocess.run(['swift', 'build', '--package-path', str(root)], check=True)
    return root / '.build/debug/Probe'


def check_resume(binary, root):
    body = b'x' * (8 * 1024 * 1024)
    requests = []

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, *args):
            pass

        def do_GET(self):
            offset = int(self.headers.get('Range', 'bytes=0-').split('=')[1].split('-')[0])
            requests.append({'range': self.headers.get('Range'), 'offset': offset})
            self.send_response(206 if offset else 200)
            self.send_header('Content-Length', str(len(body) - offset))
            self.send_header('Accept-Ranges', 'bytes')
            self.send_header('ETag', '"fixture-v1"')
            self.send_header('Last-Modified', 'Mon, 09 Nov 2026 00:00:00 GMT')
            if offset:
                self.send_header('Content-Range', f'bytes {offset}-{len(body)-1}/{len(body)}')
            self.end_headers()
            try:
                for pos in range(offset, len(body), 65536):
                    self.wfile.write(body[pos:pos + 65536])
                    self.wfile.flush()
                    time.sleep(.01)
            except (BrokenPipeError, ConnectionResetError):
                pass

    class Server(http.server.ThreadingHTTPServer):
        def handle_error(self, request, address):
            pass  # The deliberate cancellation resets a keep-alive connection.

    server = Server(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with tempfile.TemporaryDirectory(dir=root) as temporary:
            subprocess.run([str(binary), temporary, f'http://127.0.0.1:{server.server_port}/model',
                            'cancel', str(len(body))], check=True)
            assert any(item['offset'] > 0 for item in requests), 'retry restarted instead of resuming'
            assert (Path(temporary) / 'model').read_bytes() == body
    finally:
        server.shutdown()
        server.server_close()
    return requests


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--live', action='store_true')
    args = parser.parse_args()
    root = REPO / '.build/model-download-validation'
    root.mkdir(parents=True, exist_ok=True)
    binary = build_probe(root / 'probe')
    evidence = {'resume_requests': check_resume(binary, root), 'live': []}
    if args.live:
        revision = '6840bae4c5c92ee8c04faaf4db23dd0105098d7f'
        urls = [
            f'https://huggingface.co/FunAudioLLM/fsmn-vad-GGUF/resolve/{revision}/fsmn-vad.gguf',
            f'https://hf-mirror.com/FunAudioLLM/fsmn-vad-GGUF/resolve/{revision}/fsmn-vad.gguf',
            'https://www.modelscope.cn/models/FunAudioLLM/fsmn-vad-GGUF/resolve/master/fsmn-vad.gguf',
        ]
        for index, url in enumerate(urls):
            destination = root / f'live-{index}'
            subprocess.run([str(binary), str(destination), url, 'fetch', '1720512'], check=True)
            digest = hashlib.sha256((destination / 'model').read_bytes()).hexdigest()
            assert digest == '1270f2559c495f4e7b6e739541151027d360761a3fda43fc147034f5719f5479'
            evidence['live'].append({'url': url, 'sha256': digest, 'bytes': 1720512})
            if index == 0:
                # Only damage this harness's disposable cache, never application data.
                blobs = list((destination / 'cache/hub').glob('**/blobs/*'))
                blob = next(path for path in blobs if path.is_file())
                blob.write_bytes(b'x')
                (destination / 'model').unlink()
                subprocess.run([str(binary), str(destination), url, 'fetch', '1720512'], check=True)
                assert hashlib.sha256((destination / 'model').read_bytes()).hexdigest() == digest
                evidence['corrupt_hub_cache_recovered'] = True
    (root / 'evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(evidence, indent=2))


if __name__ == '__main__':
    main()
