#!/usr/bin/env python3
"""Validate device regression tests by mutating isolated copies of production Swift.

Requires stable Xcode. Never modifies the checkout's production files. Build errors
and timeouts are NOT counted as killed mutants. Logs remain in the printed temp dir.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
QUERY = "AudioInputDeviceManager"
MONITOR = "AudioDeviceChangeMonitor"
# Each replacement must match exactly once, so source drift cannot silently test nothing.
MUTATIONS = [
    (
        'input-uses-output', QUERY,
        'defaultDevice(system: system, input: true)?.id',
        'defaultDevice(system: system, input: false)?.id',
    ),
    (
        'lose-default-input-value', QUERY,
        'defaultDevice(system: system, input: true).flatMap(hardwareDevice)',
        'nil',
    ),
    (
        'notify-after-failed-stop', MONITOR,
        'self.monitorClientCount > 0',
        'true',
    ),
    (
        'accept-unknown-default', QUERY,
        'guard let device, device.id != kAudioObjectUnknown else',
        'guard let device else',
    ),
    (
        'accept-empty-name', QUERY,
        'let name = try? device.name, !name.isEmpty,',
        'let name = try? device.name,',
    ),
    (
        'wrong-transport-fallback', QUERY,
        '?? kAudioDeviceTransportTypeUnknown',
        '?? kAudioDeviceTransportTypeBuiltIn',
    ),
    (
        'discard-entire-list', QUERY,
        'return try system.devices.compactMap { device in',
        'let devices = try system.devices\n                guard devices.allSatisfy({ (try? $0.name) != nil }) else { return [] }\n                return devices.compactMap { device in',
    ),
    (
        'accept-output-only', QUERY,
        'guard hasInputChannels(device) else { return nil }',
        '// Input filtering removed.',
    ),
    (
        'require-all-buffers-input', QUERY,
        'inputStreamConfiguration.contains',
        'inputStreamConfiguration.allSatisfy',
    ),
    (
        'accept-failed-input-read', QUERY,
        '?? false',
        '?? true',
    ),
    (
        'duplicate-registration', MONITOR,
        'guard !isMonitoring else { return }',
        '// Registration guard removed.',
    ),
    (
        'unregister-first-client', MONITOR,
        'guard monitorClientCount == 0, isMonitoring else',
        'guard isMonitoring else',
    ),
    (
        'leak-failed-start-count', MONITOR,
        'monitorClientCount = max(0, monitorClientCount - 1)',
        '// Failed start count is not rolled back.',
    ),
    (
        'notify-after-stop', MONITOR,
        'guard let self, self.isMonitoring, self.monitorClientCount > 0 else',
        'guard let self else',
    ),
    (
        'drop-notification', MONITOR,
        'self.notificationCenter.post(name: Self.devicesDidChangeNotification, object: nil)',
        '// Notification dropped.',
    ),
    (
        'forget-failed-removal', MONITOR,
        '// Keep the registration so a later stop can retry without adding a duplicate.',
        'isMonitoring = false',
    ),
    (
        'skip-deinit-cleanup', MONITOR,
        'monitorClientCount = 1\n            stopMonitoring()',
        '// Deinit cleanup removed.',
    ),
    (
        'retain-monitor', MONITOR,
        'DeviceListListener { [weak self] in\n                    guard let self, self.isMonitoring, self.monitorClientCount > 0 else',
        'DeviceListListener { [self] in\n                    guard self.isMonitoring, self.monitorClientCount > 0 else',
    ),
    (
        'wrong-listener-property', MONITOR,
        'private let properties = [PropertyAddress(kAudioHardwarePropertyDevices)]',
        'private let properties = [PropertyAddress(kAudioHardwarePropertyDefaultInputDevice)]',
    ),
    (
        'wrong-callback-queue', MONITOR,
        'system.addListener(forProperties: properties, dispatchQueue: .main)',
        'system.addListener(forProperties: properties, dispatchQueue: nil)',
    ),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, help="Write JSON evidence here")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="stet-audio-mutations-"))
    source = work / "Sources/Stet"
    tests = work / "Tests/StetTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    (work / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "AudioMutationChecks", platforms: [.macOS(.v15)], targets: [
.target(name: "Stet", swiftSettings: [.unsafeFlags(["-default-isolation", "MainActor"])]),
.testTarget(name: "StetTests", dependencies: ["Stet"])
], swiftLanguageModes: [.v5])
''')
    originals = {}
    hashes = {}
    for name in [QUERY, MONITOR, "AudioHardwareDevice"]:
        path = ROOT / f"StetMac/Core/Audio/Devices/{name}.swift"
        originals[name] = path.read_text()
        shutil.copyfile(path, source / path.name)
        hashes[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    for name in [QUERY, MONITOR]:
        path = ROOT / f"StetMacTests/Core/Audio/Devices/{name}Tests.swift"
        shutil.copyfile(path, tests / path.name)
        hashes[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    env = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
    command = ["swift", "test", "--package-path", str(work), "--filter",
               "AudioInputDeviceQueryContractTests|AudioDeviceChangeMonitorTests"]

    def run(name):
        try:
            result = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=180)
            output = result.stdout
            status = ("passed" if result.returncode == 0 and "Test run with" in output
                      else "assertion-failed" if "Expectation failed" in output
                      and "Build complete!" in output else "invalid")
        except subprocess.TimeoutExpired as exc:
            output = (exc.stdout or b"").decode(errors="replace")
            status = "timeout"
        (work / f"{name}.log").write_text(output)
        evidence = [line.strip() for line in output.splitlines()
                    if "Expectation failed" in line or "Test run with" in line]
        return status, evidence

    print(f"Isolated sources and logs: {work}", flush=True)
    baseline, baseline_evidence = run("baseline")
    if baseline != "passed":
        raise SystemExit(f"Baseline did not pass: {baseline}; see {work}/baseline.log")
    results = []
    for name, target, before, after in MUTATIONS:
        original = originals[target]
        if original.count(before) != 1:
            raise SystemExit(f"Mutation anchor drifted: {name}")
        path = source / f"{target}.swift"
        path.write_text(original.replace(before, after, 1))
        try:
            status, evidence = run(name)
        finally:
            path.write_text(original)
        verdict = {"passed": "survived", "assertion-failed": "killed"}.get(status, status)
        results.append(dict(mutation=name, target=target, verdict=verdict, evidence=evidence))
        print(f"{name}: {verdict}", flush=True)
    restored, restored_evidence = run("restored")
    report = dict(source_sha256=hashes, baseline=baseline, baseline_evidence=baseline_evidence,
                  restored=restored, restored_evidence=restored_evidence, mutations=results)
    if args.report:
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"Killed {sum(r['verdict'] == 'killed' for r in results)}/{len(results)}; restored={restored}")
    return 0 if restored == "passed" and all(r["verdict"] == "killed" for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
