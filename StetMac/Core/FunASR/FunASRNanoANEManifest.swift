import Foundation

nonisolated struct FunASRNanoANEManifest: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        let path: String
        let size: Int64
        let sha256: String
    }
    static let modelID = "funasr-nano-ane-v1"
    static let modelContract = "nano-gguf-ane-v1-buckets"
    static let packageName = "FunASRNanoANE-v1.mlpackage"
    static let compiledName = "FunASRNanoANE-v1.mlmodelc"
    static let sourceHash = "f92f91d01a24fbed6c863495b2ee8c6a6788144a02858b75743f0946668de8a2"
    static let decoderHash = "cc5057552aa9dddedcda73ea8889854e8a257eb07d0a561b7234465c1e856f22"
    let schemaVersion: Int
    let modelID: String
    let contract: String
    let minimumMacOSMajor: Int
    let sourceEncoderSHA256: String
    let decoderSHA256: String
    let packageDirectory: String
    let files: [File]

    func validate() throws {
        guard schemaVersion == 1, modelID == Self.modelID, contract == Self.modelContract,
            minimumMacOSMajor == 15, sourceEncoderSHA256 == Self.sourceHash, decoderSHA256 == Self.decoderHash,
            packageDirectory == Self.packageName, !files.isEmpty, files.count <= 100,
            Set(files.map { $0.path.precomposedStringWithCanonicalMapping.lowercased() }).count == files.count,
            files.contains(where: { $0.path == "Manifest.json" }),
            files.contains(where: { $0.path == "Data/com.apple.CoreML/model.mlmodel" })
        else { throw ANEModelInstallError.invalidManifest }
        var total: Int64 = 0
        for file in files {
            guard Self.isSafePath(file.path), file.size > 0, file.size <= 1_073_741_824,
                file.sha256.count == 64, file.sha256.allSatisfy(\.isHexDigit)
            else { throw ANEModelInstallError.invalidManifest }
            total += file.size
        }
        guard total <= 1_073_741_824 else { throw ANEModelInstallError.invalidManifest }
    }

    static func isSafePath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && !path.contains("\\") && !path.contains("\0")
            && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

nonisolated struct FunASRNanoANECatalog: Codable, Sendable {
    struct Release: Codable, Sendable {
        let manifestURL: URL
        let manifestSize: Int64
        let manifestSHA256: String

        func validate() throws {
            guard manifestURL.scheme == "https", manifestURL.user == nil, manifestURL.password == nil,
                manifestURL.query == nil, manifestURL.fragment == nil,
                manifestSize > 0, manifestSize < 1_048_576,
                manifestSHA256.count == 64, manifestSHA256.allSatisfy(\.isHexDigit),
                let file = ModelFileTransport.HubFile(manifestURL), file.host.host == "huggingface.co",
                file.revision.count == 40, file.revision.allSatisfy(\.isHexDigit)
            else { throw ANEModelInstallError.invalidManifest }
        }
    }
    let schemaVersion: Int
    let release: Release?

    static func bundled() -> Release? {
        guard let url = Bundle.main.url(forResource: "funasr-ane-release", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let catalog = try? JSONDecoder().decode(Self.self, from: data), catalog.schemaVersion == 1,
            let release = catalog.release, (try? release.validate()) != nil
        else { return nil }
        return release
    }
}

nonisolated enum ANEModelInstallError: Error, LocalizedError {
    case unsupported, unavailable, invalidManifest, invalidPackage, invalidModel, noANE, busy, missingCPUModel,
        incompatibleCPUModel,
        alreadyInstalled
    var errorDescription: String? {
        switch self {
        case .unsupported: "Neural Engine acceleration requires Apple Silicon and macOS 15 or later."
        case .unavailable: "No acceleration model download is published yet. Import a local candidate instead."
        case .invalidManifest: "The acceleration model manifest is invalid or incompatible."
        case .invalidPackage: "The acceleration model package is incomplete or contains unsafe file paths."
        case .invalidModel: "The acceleration model failed validation. CPU transcription remains available."
        case .noANE: "This model could not be assigned to the Neural Engine on this Mac."
        case .incompatibleCPUModel:
            "The installed Nano model version does not match this acceleration model. CPU transcription remains available."
        case .alreadyInstalled: "Disable the current acceleration model before replacing it."
        case .busy: "Another acceleration model operation is in progress."
        case .missingCPUModel: "Download the standard Fun-ASR Nano model before installing acceleration."
        }
    }
}

nonisolated enum ANEInstallationProgress: Equatable, Sendable {
    case copying(Double), compiling, waitingForIdle, preparing(Int, Int), ready, disabled
}

nonisolated struct ANEModelReadiness: Codable, Sendable {
    static let fileName = ".funasr-ane-ready-v1.json"
    let schemaVersion: Int
    let modelID: String
    let contract: String
    let manifestHash: String
    let osVersion: String
    let applicationBuild: String
    let enabled: Bool

    static var supported: Bool {
        #if arch(arm64)
            if #available(macOS 15, *) { return true }
        #endif
        return false
    }

    static var currentBuild: String {
        let bundle = Bundle.main
        let executable = bundle.executableURL
        let attributes = executable.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path) }
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return ModelFileDownloader.digest(
            "\(bundle.bundleIdentifier ?? "local"):\(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "development"):\(bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "development"):\(executable?.path ?? ""):\(modified)"
        )
    }

    static func make(manifestHash: String, enabled: Bool = true) -> Self {
        Self(
            schemaVersion: 1, modelID: FunASRNanoANEManifest.modelID, contract: FunASRNanoANEManifest.modelContract,
            manifestHash: manifestHash, osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            applicationBuild: currentBuild, enabled: enabled)
    }

    static func read(in directory: URL) -> Self? {
        guard let receipt = installed(in: directory), receipt.enabled,
            receipt.osVersion == ProcessInfo.processInfo.operatingSystemVersionString,
            receipt.applicationBuild == currentBuild
        else { return nil }
        return receipt
    }

    static func installed(in directory: URL) -> Self? {
        guard supported,
            let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
            let receipt = try? JSONDecoder().decode(Self.self, from: data), receipt.schemaVersion == 1,
            receipt.modelID == FunASRNanoANEManifest.modelID, receipt.contract == FunASRNanoANEManifest.modelContract,
            receipt.manifestHash.count == 64, receipt.manifestHash.allSatisfy(\.isHexDigit),
            (try? directory.appendingPathComponent(FunASRNanoANEManifest.compiledName)
                .resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else { return nil }
        return receipt
    }

    static func remove(in directory: URL) throws {
        let url = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    func write(in directory: URL) throws {
        try JSONEncoder().encode(self).write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }
}
