import CryptoKit
import Foundation
import Testing
import StetASR
@testable import Stet

@Suite(.enabled(if: ANEModelReadiness.supported))
struct FunASRNanoANEInstallerTests {
    @Test func localCandidateWarmsFinalPathBeforePublishingReadiness() async throws {
        let fixture = try ANEInstallFixture()
        defer { fixture.remove() }
        let recorder = ANEPreparationRecorder()
        let installer = fixture.installer { url, progress in
            #expect(url == fixture.compiled)
            #expect(ANEModelReadiness.read(in: fixture.models) == nil)
            let files = try fixture.manager.resolvedModelFiles()
            #expect(files.encoder.pathExtension == "gguf")
            await recorder.record(url)
            progress(.preparing(4, 4))
        }
        try await installer.importCandidate(at: fixture.candidate) { _ in }
        #expect(await recorder.urls == [fixture.compiled])
        #expect(await installer.status().ready)
        #expect(try fixture.manager.resolvedModelFiles().encoder == fixture.compiled)
        try await installer.importCandidate(at: fixture.candidate) { _ in }
        #expect(await recorder.urls.count == 1)
        #expect(fixture.manager.isModelDownloaded())
    }

    @Test func failedPreparationRestoresPreviousUnreadyModelAndKeepsCPUFiles() async throws {
        let fixture = try ANEInstallFixture()
        defer { fixture.remove() }
        try fixture.makePreviousModel()
        let installer = fixture.installer { _, _ in throw ANEModelInstallError.invalidModel }
        await #expect(throws: ANEModelInstallError.self) {
            try await installer.importCandidate(at: fixture.candidate) { _ in }
        }
        #expect(try String(contentsOf: fixture.compiled.appendingPathComponent("old"), encoding: .utf8) == "previous")
        #expect(!(await installer.status().ready))
        #expect(fixture.manager.isModelDownloaded())
        #expect(try fixture.manager.resolvedModelFiles().encoder.pathExtension == "gguf")
    }

    @Test func cancellationAfterPlacementRollsBackWithoutActivatingCandidate() async throws {
        let fixture = try ANEInstallFixture()
        defer { fixture.remove() }
        try fixture.makePreviousModel()
        let recorder = ANEPreparationRecorder()
        let installer = fixture.installer { url, _ in
            await recorder.record(url)
            try await Task.sleep(for: .seconds(30))
        }
        let task = Task { try await installer.importCandidate(at: fixture.candidate) { _ in } }
        try #require(await TestSupport.eventuallyAsync { await recorder.urls.count == 1 })
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(ANEModelReadiness.read(in: fixture.models) == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.compiled.appendingPathComponent("old").path))
        #expect(fixture.manager.isModelDownloaded())
    }

    @Test func checksumFailureDoesNotCompileOrReplaceFiles() async throws {
        let fixture = try ANEInstallFixture()
        defer { fixture.remove() }
        try fixture.makePreviousModel()
        try Data("corrupt".utf8).write(
            to: fixture.package.appendingPathComponent("Data/com.apple.CoreML/model.mlmodel"))
        let installer = fixture.installer { _, _ in Issue.record("Corrupt input reached preparation") }
        await #expect(throws: ModelFileDownloadError.self) {
            try await installer.importCandidate(at: fixture.candidate) { _ in }
        }
        #expect(FileManager.default.fileExists(atPath: fixture.compiled.appendingPathComponent("old").path))
        #expect(ANEModelReadiness.read(in: fixture.models) == nil)
    }

    @Test func traversalAndSymlinkOutsideCandidateAreRejected() async throws {
        let fixture = try ANEInstallFixture()
        defer { fixture.remove() }
        #expect(!FunASRNanoANEManifest.isSafePath("../model"))
        #expect(!FunASRNanoANEManifest.isSafePath("/model"))
        #expect(!FunASRNanoANEManifest.isSafePath("Data/../model"))
        let model = fixture.package.appendingPathComponent("Data/com.apple.CoreML/model.mlmodel")
        let outside = fixture.root.appendingPathComponent("outside")
        try FileManager.default.moveItem(at: model, to: outside)
        try FileManager.default.createSymbolicLink(at: model, withDestinationURL: outside)
        let installer = fixture.installer { _, _ in Issue.record("Unsafe path reached preparation") }
        await #expect(throws: ANEModelInstallError.self) {
            try await installer.importCandidate(at: fixture.candidate) { _ in }
        }
        #expect(ANEModelReadiness.read(in: fixture.models) == nil)
    }

    @Test func disableAndReprepareReuseInstalledModel() async throws {
        let fixture = try ANEInstallFixture()
        defer { fixture.remove() }
        let recorder = ANEPreparationRecorder()
        let installer = fixture.installer { url, _ in await recorder.record(url) }
        try await installer.importCandidate(at: fixture.candidate) { _ in }
        try await installer.disable { _ in }
        let disabled = await installer.status()
        #expect(!disabled.ready && disabled.canPrepareInstalled)
        #expect(try fixture.manager.resolvedModelFiles().encoder.pathExtension == "gguf")
        try FileManager.default.removeItem(at: fixture.candidate)
        try await installer.prepareInstalled { _ in }
        #expect(await installer.status().ready)
        #expect(await recorder.urls.count == 2)
    }

    @Test func incompatibleStandardWeightsAreRejectedBeforeInstallingAcceleration() async throws {
        let fixture = try ANEInstallFixture()
        defer { fixture.remove() }
        await #expect(throws: ANEModelInstallError.self) {
            try await FunASRNanoANEInstaller.validateCPUAssets(in: fixture.models)
        }
        #expect(fixture.manager.isModelDownloaded())
        #expect(ANEModelReadiness.read(in: fixture.models) == nil)
    }

    @Test func unavailableCatalogNeverStartsNetwork() async throws {
        let fixture = try ANEInstallFixture()
        defer { fixture.remove() }
        let installer = fixture.installer { _, _ in Issue.record("Unexpected preparation") }
        #expect(!(await installer.status().downloadAvailable))
        await #expect(throws: ANEModelInstallError.self) { try await installer.download { _ in } }
        #expect(!FileManager.default.fileExists(atPath: fixture.compiled.path))
    }

    @Test func remoteManifestAndFilesUseTheSharedDownloader() async throws {
        let fixture = try ANEInstallFixture()
        defer { fixture.remove() }
        let data = try Data(contentsOf: fixture.candidate.appendingPathComponent("manifest.json"))
        let release = FunASRNanoANECatalog.Release(
            manifestURL: URL(
                string: "https://huggingface.co/stet/test/resolve/\(String(repeating: "a", count: 40))/manifest.json")!,
            manifestSize: Int64(data.count), manifestSHA256: ANEInstallFixture.hash(data))
        let downloader = ModelFileDownloader(cache: fixture.root.appendingPathComponent("cache")) { url, staging, _ in
            let source: URL
            if url.lastPathComponent == "manifest.json" {
                source = fixture.candidate.appendingPathComponent("manifest.json")
            } else {
                let prefix = FunASRNanoANEManifest.packageName + "/"
                let relative = String(url.path.components(separatedBy: prefix).last!)
                source = fixture.package.appendingPathComponent(relative)
            }
            try FileManager.default.copyItem(at: source, to: staging)
        }
        let installer = FunASRNanoANEInstaller(
            directoryProvider: { fixture.models }, release: release, downloader: downloader,
            cache: fixture.root.appendingPathComponent("cache"), validateCPU: fixture.validateCPU,
            compile: fixture.compile,
            prepare: { _, _ in },
            whenIdle: { action in
                try action(); return true
            })
        try await installer.download { _ in }
        #expect(await installer.status().ready)
    }

    @Test func systemOrAppBuildChangeRequiresPreparationAgain() throws {
        let fixture = try ANEInstallFixture()
        defer { fixture.remove() }
        try fixture.makePreviousModel()
        let stale = ANEModelReadiness(
            schemaVersion: 1, modelID: FunASRNanoANEManifest.modelID, contract: FunASRNanoANEManifest.modelContract,
            manifestHash: String(repeating: "a", count: 64), osVersion: "old system", applicationBuild: "old app",
            enabled: true)
        try stale.write(in: fixture.models)
        #expect(ANEModelReadiness.installed(in: fixture.models) != nil)
        #expect(ANEModelReadiness.read(in: fixture.models) == nil)
        #expect(try fixture.manager.resolvedModelFiles().encoder.pathExtension == "gguf")
    }
}

private nonisolated struct ANEInstallFixture: Sendable {
    let root: URL
    let models: URL
    let candidate: URL
    var package: URL { candidate.appendingPathComponent(FunASRNanoANEManifest.packageName) }
    var compiled: URL { models.appendingPathComponent(FunASRNanoANEManifest.compiledName) }
    var manager: FunASRNanoModelManager { FunASRNanoModelManager(modelsDirectoryProvider: { models }) }
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        models = root.appendingPathComponent("models")
        candidate = root.appendingPathComponent("candidate")
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        for name in ["funasr-encoder-f16.gguf", "qwen3-0.6b-q4km.gguf", "fsmn-vad.gguf"] {
            try Data("existing CPU asset".utf8).write(to: models.appendingPathComponent(name))
        }
        let values = ["Manifest.json": Data("{}".utf8), "Data/com.apple.CoreML/model.mlmodel": Data("model".utf8)]
        var files: [FunASRNanoANEManifest.File] = []
        for (path, data) in values {
            let url = package.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            files.append(.init(path: path, size: Int64(data.count), sha256: Self.hash(data)))
        }
        let manifest = FunASRNanoANEManifest(
            schemaVersion: 1, modelID: FunASRNanoANEManifest.modelID, contract: FunASRNanoANEManifest.modelContract,
            minimumMacOSMajor: 15, sourceEncoderSHA256: FunASRNanoANEManifest.sourceHash,
            decoderSHA256: FunASRNanoANEManifest.decoderHash,
            packageDirectory: FunASRNanoANEManifest.packageName, files: files.sorted { $0.path < $1.path })
        try JSONEncoder().encode(manifest).write(to: candidate.appendingPathComponent("manifest.json"))
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func makePreviousModel() throws {
        try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
        try Data("previous".utf8).write(to: compiled.appendingPathComponent("old"))
    }
    var validateCPU: FunASRNanoANEInstaller.ValidateCPU {
        { _ in guard manager.isModelDownloaded() else { throw ANEModelInstallError.missingCPUModel } }
    }
    var compile: FunASRNanoANEInstaller.Compile {
        { _ in
            let output = root.appendingPathComponent("compiled-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try Data("new model".utf8).write(to: output.appendingPathComponent("new"))
            return output
        }
    }
    func installer(prepare: @escaping FunASRNanoANEInstaller.Prepare) -> FunASRNanoANEInstaller {
        FunASRNanoANEInstaller(
            directoryProvider: { models }, cache: root.appendingPathComponent("cache"),
            validateCPU: validateCPU, compile: compile, prepare: prepare,
            whenIdle: { action in
                try action(); return true
            })
    }
}

private actor ANEPreparationRecorder {
    var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
}
