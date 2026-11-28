import CryptoKit
import Foundation
import StetASR

nonisolated struct ANEModelInstallationStatus: Equatable, Sendable {
    let supported: Bool
    let ready: Bool
    let canPrepareInstalled: Bool
    let downloadAvailable: Bool
}

nonisolated protocol ANEModelInstalling: Actor {
    func status() async -> ANEModelInstallationStatus
    func importCandidate(at directory: URL, progress: @escaping @Sendable (ANEInstallationProgress) -> Void)
        async throws
    func download(progress: @escaping @Sendable (ANEInstallationProgress) -> Void) async throws
    func prepareInstalled(progress: @escaping @Sendable (ANEInstallationProgress) -> Void) async throws
    func disable(progress: @escaping @Sendable (ANEInstallationProgress) -> Void) async throws
}

/// Installs only a verified source package; no archive extraction or runtime model downloads.
/// Readiness is published after warming at the final path, and only while ASR is idle.
actor FunASRNanoANEInstaller: ANEModelInstalling {
    static let shared = FunASRNanoANEInstaller(release: FunASRNanoANECatalog.bundled())

    typealias ProgressHandler = @Sendable (ANEInstallationProgress) -> Void
    typealias ValidateCompanions = @Sendable (URL) async throws -> Void
    typealias Compile = @Sendable (URL) async throws -> URL
    typealias Prepare = @Sendable (URL, @escaping ProgressHandler) async throws -> Void
    typealias IdleAction = @Sendable (@escaping @Sendable () throws -> Void) async throws -> Bool
    typealias ReadyAction = @Sendable (URL) async -> Void

    private let directoryProvider: @Sendable () throws -> URL
    private let release: FunASRNanoANECatalog.Release?
    private let downloader: ModelFileDownloader
    private let localDownloader: ModelFileDownloader
    private let validateCompanions: ValidateCompanions
    private let compile: Compile
    private let prepare: Prepare
    private let whenIdle: IdleAction
    private let onReady: ReadyAction
    private let cache: URL
    private var busy = false

    init(
        directoryProvider: @escaping @Sendable () throws -> URL = {
            try FunASRNanoModelManager().modelFiles().encoder.deletingLastPathComponent()
        },
        release: FunASRNanoANECatalog.Release? = nil,
        downloader: ModelFileDownloader = .shared,
        cache: URL = ModelFileTransport.defaultCache,
        validateCompanions: @escaping ValidateCompanions = FunASRNanoANEInstaller.validateCompanionAssets,
        compile: @escaping Compile = FunASRNanoANEPreparation.compile,
        prepare: @escaping Prepare = FunASRNanoANEPreparation.prepare,
        whenIdle: @escaping IdleAction = { action in
            try await FunASRNanoContextManager.shared.performModelMaintenance(action)
        },
        onReady: @escaping ReadyAction = { directory in
            await FunASRNanoContextManager.shared.scheduleResidentEncoderPreload(in: directory)
        }
    ) {
        self.directoryProvider = directoryProvider
        self.release = release
        self.downloader = downloader
        self.cache = cache
        self.validateCompanions = validateCompanions
        self.compile = compile
        self.prepare = prepare
        self.whenIdle = whenIdle
        self.onReady = onReady
        localDownloader = ModelFileDownloader(cache: cache) { source, destination, progress in
            guard source.isFileURL else { throw ANEModelInstallError.invalidPackage }
            try FileManager.default.copyItem(at: source, to: destination)
            progress(1)
        }
    }

    func status() -> ANEModelInstallationStatus {
        let directory = try? directoryProvider()
        return ANEModelInstallationStatus(
            supported: ANEModelReadiness.supported,
            ready: directory.flatMap { ANEModelReadiness.read(in: $0) } != nil,
            canPrepareInstalled: directory.flatMap { ANEModelReadiness.installed(in: $0) } != nil,
            downloadAvailable: release != nil)
    }

    func importCandidate(at source: URL, progress: @escaping ProgressHandler) async throws {
        try begin()
        defer { busy = false }
        let manifest = source.appendingPathComponent("manifest.json")
        try Self.checkLocalFile(manifest, within: source)
        let size = try manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size < 1_048_576 else { throw ANEModelInstallError.invalidManifest }
        try await install(data: Data(contentsOf: manifest), source: source, local: true, progress: progress)
    }

    func download(progress: @escaping ProgressHandler) async throws {
        guard let release else { throw ANEModelInstallError.unavailable }
        try release.validate()
        try begin()
        defer { busy = false }
        progress(.copying(0))
        let path = cache.appendingPathComponent("ane-manifests/\(release.manifestSHA256).json")
        _ = try await downloader.file(
            ModelFileRequest(official: release.manifestURL, size: release.manifestSize, sha256: release.manifestSHA256),
            at: path)
        try await install(
            data: Data(contentsOf: path), source: release.manifestURL.deletingLastPathComponent(), local: false,
            progress: progress)
    }

    func updateEnabledRelease(in directory: URL) async throws {
        guard let previous = release?.replacesManifestSHA256,
            let receipt = ANEModelReadiness.installed(in: directory),
            receipt.enabled, receipt.manifestHash == previous
        else { return }
        try await download { _ in }
    }

    func prepareInstalled(progress: @escaping ProgressHandler) async throws {
        try begin()
        defer { busy = false }
        let directory = try directoryProvider()
        guard let receipt = ANEModelReadiness.installed(in: directory) else { throw ANEModelInstallError.invalidModel }
        try await validateCompanions(directory)
        if ANEModelReadiness.read(in: directory) != nil {
            await onReady(directory)
            progress(.ready)
            return
        }
        try await prepare(receipt.compiledURL(in: directory), progress)
        try Task.checkCancellation()
        try await waitForIdle(progress: progress) {
            try receipt.refreshed().write(in: directory)
        }
        await onReady(directory)
        progress(.ready)
    }

    func disable(progress: @escaping ProgressHandler) async throws {
        try begin()
        defer { busy = false }
        let directory = try directoryProvider()
        guard let receipt = ANEModelReadiness.installed(in: directory) else { progress(.disabled); return }
        try await waitForIdle(progress: progress) {
            try receipt.refreshed(enabled: false).write(in: directory)
        }
        progress(.disabled)
    }

    private func begin() throws {
        guard ANEModelReadiness.supported else { throw ANEModelInstallError.unsupported }
        guard !busy else { throw ANEModelInstallError.busy }
        try Task.checkCancellation()
        busy = true
    }

    nonisolated static func validateCompanionAssets(in directory: URL) async throws {
        let task = Task.detached(priority: .utility) {
            let manager = FunASRNanoModelManager(modelsDirectoryProvider: { directory })
            guard manager.missingCompanionFiles(in: directory).isEmpty else {
                throw ANEModelInstallError.missingCompanions
            }
            let files = try manager.modelFiles()
            try Task.checkCancellation()
            guard try ModelFileDownloader.sha256(of: files.languageModel) == FunASRNanoANEManifest.decoderHash
            else { throw ANEModelInstallError.incompatibleDecoder }
            try Task.checkCancellation()
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func install(data: Data, source: URL, local: Bool, progress: @escaping ProgressHandler) async throws {
        let manifest = try JSONDecoder().decode(FunASRNanoANEManifest.self, from: data)
        try manifest.validate()
        let directory = try directoryProvider()
        try await validateCompanions(directory)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try await ModelDownloadLock.withLock(key: "ane-install:\(directory.path)", cache: cache) {
            try await self.installLocked(
                manifest, hash: hash, source: source, local: local, in: directory, progress: progress)
        }
    }

    private func installLocked(
        _ manifest: FunASRNanoANEManifest, hash: String, source: URL, local: Bool, in directory: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        let previous = ANEModelReadiness.installed(in: directory)
        if let previous, previous.manifestHash == hash {
            if ANEModelReadiness.read(in: directory) == nil {
                try await prepare(previous.compiledURL(in: directory), progress)
                try await waitForIdle(progress: progress) { try previous.refreshed().write(in: directory) }
            }
            await onReady(directory)
            progress(.ready)
            return
        }
        if let previous, previous.enabled {
            guard !local, release?.manifestSHA256 == hash, release?.replacesManifestSHA256 == previous.manifestHash
            else { throw ANEModelInstallError.alreadyInstalled }
        }
        let manager = FileManager.default
        let working = directory.appendingPathComponent(".ane-install/\(hash)", isDirectory: true)
        let package = working.appendingPathComponent(manifest.packageDirectory, isDirectory: true)
        let sourcePackage = source.appendingPathComponent(manifest.packageDirectory, isDirectory: true)
        let total = Double(manifest.files.reduce(Int64(0)) { $0 + $1.size })
        var completed: Int64 = 0
        for file in manifest.files {
            try Task.checkCancellation()
            let origin = sourcePackage.appendingPathComponent(file.path)
            if local { try Self.checkLocalFile(origin, within: source) }
            let request =
                local
                ? ModelFileRequest(sources: [origin], size: file.size, sha256: file.sha256)
                : ModelFileRequest(official: origin, size: file.size, sha256: file.sha256)
            let base = Double(completed)
            _ = try await (local ? localDownloader : downloader).file(
                request, at: package.appendingPathComponent(file.path)
            ) { fraction in
                progress(.copying((base + fraction * Double(file.size)) / total))
            }
            completed += file.size
        }
        progress(.compiling)
        let compiled = try await compile(package)
        defer { try? manager.removeItem(at: compiled) }
        try Task.checkCancellation()
        let pending = working.appendingPathComponent("pending.mlmodelc", isDirectory: true)
        if manager.fileExists(atPath: pending.path) { try manager.removeItem(at: pending) }
        try manager.copyItem(at: compiled, to: pending)
        // Prepare at a stable final path while the previous receipt still selects its model.
        let receipt = ANEModelReadiness.make(manifestHash: hash, versionedPath: true)
        let destination = receipt.compiledURL(in: directory)
        if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
        try manager.moveItem(at: pending, to: destination)
        do {
            try await prepare(destination, progress)
            try await waitForIdle(progress: progress) {
                try receipt.write(in: directory)
                if let previous { try? manager.removeItem(at: previous.compiledURL(in: directory)) }
            }
        } catch {
            try? manager.removeItem(at: destination)
            throw error
        }
        await onReady(directory)
        progress(.ready)
    }

    private func waitForIdle(progress: @escaping ProgressHandler, action: @escaping @Sendable () throws -> Void)
        async throws
    {
        while true {
            try Task.checkCancellation()
            if try await whenIdle(action) { return }
            progress(.waitingForIdle)
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    private nonisolated static func checkLocalFile(_ url: URL, within root: URL) throws {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard resolved.hasPrefix(base), values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ANEModelInstallError.invalidPackage
        }
    }
}
