#!/usr/bin/env python3
"""Validate real candidate compilation/preparation and unchanged decoder on this Mac.

Uses an isolated model directory. App session/lease coordination is covered by
application tests; this standalone probe has no active app sessions.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

REPO = Path(__file__).resolve().parents[2]
SOURCES = [
    'Core/Models/ModelFileDownload.swift', 'Core/Models/ModelFileTransport.swift',
    'Core/FunASR/FunASRNanoModelManager.swift', 'Core/FunASR/FunASRNanoANEManifest.swift',
    'Core/FunASR/FunASRNanoANEPreparation.swift', 'Core/FunASR/FunASRNanoANEInstaller.swift',
]
MAIN = '''import Foundation
import StetASR
// Only satisfies the default-argument symbol. An explicit idle action is supplied;
// production app coordination is separately exercised by application tests.
actor FunASRNanoContextManager {
 static let shared = FunASRNanoContextManager()
 func performModelMaintenance(_ action: @Sendable () throws -> Void) async throws -> Bool { try action(); return true }
}
let models = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let candidate = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let audio = URL(fileURLWithPath: CommandLine.arguments[3])
let reportURL = URL(fileURLWithPath: CommandLine.arguments[4])
let installer = FunASRNanoANEInstaller(directoryProvider: { models },
 cache: models.deletingLastPathComponent().appendingPathComponent("cache"),
 whenIdle: { action in try action(); return true })
let start = Date()
try await installer.importCandidate(at: candidate) { print("phase=\\($0)"); fflush(nil) }
let preparationSeconds = Date().timeIntervalSince(start)
let readyStatus = await installer.status()
precondition(readyStatus.ready)
let manager = FunASRNanoModelManager(modelsDirectoryProvider: { models })
let selected = try manager.resolvedModelFiles()
precondition(selected.encoder.pathExtension == "mlmodelc")
let ane = FunASRNanoRecognizer(modelFiles: selected)
try await ane.prepare()
let backend = await ane.encoderBackend()
precondition(backend == "coreml-cpu-and-ne")
let accelerated = try await ane.transcribe(audioFileURL: audio)
await ane.releaseResources()
let cpu = FunASRNanoRecognizer(modelFiles: try manager.modelFiles())
let reference = try await cpu.transcribe(audioFileURL: audio)
await cpu.releaseResources()
precondition(accelerated == reference)
try await installer.disable { print("disable=\\($0)") }
let disabledFiles = try manager.resolvedModelFiles()
precondition(disabledFiles.encoder.pathExtension == "gguf")
try await installer.prepareInstalled { print("reprepare=\\($0)"); fflush(nil) }
let preparedStatus = await installer.status()
precondition(preparedStatus.ready)
let report: [String: Any] = ["preparation_seconds": preparationSeconds, "backend": backend,
 "text_equal": accelerated == reference, "transcript": accelerated, "disable_and_reprepare": true]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: reportURL)
print(String(data: try Data(contentsOf: reportURL), encoding: .utf8)!)
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--models', type=Path, required=True)
    parser.add_argument('--audio', type=Path, required=True)
    args = parser.parse_args()
    root = REPO / '.build/ane-install-validation'
    models = root / 'models'
    source = root / 'probe/Sources/Probe'
    models.mkdir(parents=True, exist_ok=True)
    source.mkdir(parents=True, exist_ok=True)
    for name in ['funasr-encoder-f16.gguf', 'qwen3-0.6b-q4km.gguf', 'fsmn-vad.gguf']:
        target = models / name
        if not target.exists():
            # Read-only model inputs; hard links avoid another gigabyte of copies.
            os.link(args.models.resolve() / name, target)
    package = '''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "ANEInstallProbe", platforms: [.macOS(.v15)], dependencies: [
 .package(path: %s), .package(url: "https://github.com/huggingface/swift-huggingface.git", exact: "1.0.0")],
 targets: [.executableTarget(name: "Probe", dependencies: [
 .product(name: "StetCore", package: "StetEngine"), .product(name: "StetASR", package: "StetEngine"),
 .product(name: "HuggingFace", package: "swift-huggingface")], swiftSettings: [.swiftLanguageMode(.v5), .defaultIsolation(MainActor.self)])])
''' % json.dumps(str(REPO / 'Packages/StetEngine'))
    (root / 'probe/Package.swift').write_text(package)
    (source / 'main.swift').write_text(MAIN)
    for relative in SOURCES:
        target = source / Path(relative).name
        if not target.exists():
            target.symlink_to(REPO / 'StetMac' / relative)
    subprocess.run(['swift', 'run', '--package-path', str(root / 'probe'), 'Probe', str(models),
                    str(args.candidate.resolve()), str(args.audio.resolve()), str(root / 'result.json')], check=True)


if __name__ == '__main__':
    main()
