import Foundation

struct LocalWhisperModelDescriptor: Sendable, Equatable {
    let displayName: String
    let fileName: String

    nonisolated static let `default` = LocalWhisperModelDescriptor(
        displayName: "Whisper tiny q5_1",
        fileName: "ggml-tiny-q5_1.bin"
    )

    /// Returns a descriptor inferred from an arbitrary file URL.
    nonisolated static func from(url: URL) -> LocalWhisperModelDescriptor {
        LocalWhisperModelDescriptor(
            displayName: url.lastPathComponent,
            fileName: url.lastPathComponent
        )
    }
}

enum LocalWhisperModelStatus: Sendable, Equatable {
    case ready(localURL: URL)
    case missing(expectedURL: URL)
    case runtimeUnavailable(expectedURL: URL)
}

enum LocalWhisperError: LocalizedError, Equatable, Sendable {
    case modelDirectoryUnavailable
    case modelMissing(expectedURL: URL)
    case runtimeUnavailable
    case audioPreparationFailed
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .modelDirectoryUnavailable:
            return "Stet could not resolve the Local Whisper models directory."
        case .modelMissing(let expectedURL):
            return
                "Local Whisper model not found. Place the model at \(expectedURL.path)."
        case .runtimeUnavailable:
            return "Local Whisper runtime is not linked in this build."
        case .audioPreparationFailed:
            return "Stet could not prepare audio for Local Whisper transcription."
        case .transcriptionFailed:
            return "Local Whisper transcription failed."
        }
    }
}

struct LocalWhisperModelManager: Sendable {
    private let model: LocalWhisperModelDescriptor
    private let modelsDirectoryProvider: @Sendable () throws -> URL
    private let runtimeAvailableProvider: @Sendable () -> Bool
    /// Optional absolute path override stored in UserDefaults.
    private let customPathProvider: @Sendable () -> String?

    init(
        model: LocalWhisperModelDescriptor = .default,
        modelsDirectoryProvider: (@Sendable () throws -> URL)? = nil,
        runtimeAvailableProvider: (@Sendable () -> Bool)? = nil,
        customPathProvider: (@Sendable () -> String?)? = nil
    ) {
        self.model = model
        self.modelsDirectoryProvider =
            modelsDirectoryProvider
            ?? {
                guard
                    let applicationSupportURL = FileManager.default.urls(
                        for: .applicationSupportDirectory,
                        in: .userDomainMask
                    ).first
                else {
                    throw LocalWhisperError.modelDirectoryUnavailable
                }

                return applicationSupportURL
                    .appendingPathComponent("Stet", isDirectory: true)
                    .appendingPathComponent("Models", isDirectory: true)
            }
        self.runtimeAvailableProvider = runtimeAvailableProvider ?? { LocalWhisperEngineFactory.isRuntimeAvailable }
        self.customPathProvider =
            customPathProvider
            ?? { UserDefaults.standard.string(forKey: MacPreferences.localWhisperModelPath) }
    }

    /// Saves a custom model path to UserDefaults.
    nonisolated static func saveCustomModelPath(_ path: String?) {
        if let path {
            UserDefaults.standard.set(path, forKey: MacPreferences.localWhisperModelPath)
        } else {
            UserDefaults.standard.removeObject(forKey: MacPreferences.localWhisperModelPath)
        }
    }

    /// Returns the custom path URL when it is set and the file exists.
    private func resolvedCustomURL() -> URL? {
        guard let path = customPathProvider(), !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var modelDescriptor: LocalWhisperModelDescriptor {
        if let customURL = resolvedCustomURL() {
            return .from(url: customURL)
        }
        return model
    }

    func status() throws -> LocalWhisperModelStatus {
        // Custom path takes priority over the default Stet models directory.
        if let customURL = resolvedCustomURL() {
            guard runtimeAvailableProvider() else {
                return .runtimeUnavailable(expectedURL: customURL)
            }
            return .ready(localURL: customURL)
        }

        let expectedURL = try expectedModelURL()

        guard runtimeAvailableProvider() else {
            return .runtimeUnavailable(expectedURL: expectedURL)
        }

        if FileManager.default.fileExists(atPath: expectedURL.path) {
            return .ready(localURL: expectedURL)
        }

        return .missing(expectedURL: expectedURL)
    }

    func resolvedModelURL() throws -> URL {
        switch try status() {
        case .ready(let localURL):
            return localURL
        case .missing(let expectedURL):
            throw LocalWhisperError.modelMissing(expectedURL: expectedURL)
        case .runtimeUnavailable:
            throw LocalWhisperError.runtimeUnavailable
        }
    }

    func expectedModelURL() throws -> URL {
        if let customURL = resolvedCustomURL() {
            return customURL
        }
        let modelsDirectoryURL = try ensureModelsDirectoryExists()
        return modelsDirectoryURL.appendingPathComponent(model.fileName, isDirectory: false)
    }

    func statusMessage() -> String {
        let expectedPath: String

        do {
            expectedPath = try expectedModelURL().path
        } catch {
            return LocalWhisperError.modelDirectoryUnavailable.localizedDescription
        }

        do {
            switch try status() {
            case .ready:
                return "Local Whisper model is available at \(expectedPath)."
            case .missing:
                return "Place \(model.fileName) at \(expectedPath)."
            case .runtimeUnavailable:
                return "Local Whisper runtime is not linked in this build. Expected model path: \(expectedPath)."
            }
        } catch {
            return error.localizedDescription
        }
    }

    func needsAttention() -> Bool {
        do {
            switch try status() {
            case .ready:
                return false
            case .missing, .runtimeUnavailable:
                return true
            }
        } catch {
            return true
        }
    }

    @discardableResult
    func ensureModelsDirectoryExists() throws -> URL {
        let url = try modelsDirectory()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func modelsDirectory() throws -> URL {
        try modelsDirectoryProvider()
    }
}
