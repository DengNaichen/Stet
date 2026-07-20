import Combine
import Foundation

enum MobileDictationEngine: String, CaseIterable, Identifiable, Sendable {
    case senseVoice
    case funASRRealtime

    var id: Self { self }

    var displayName: String {
        switch self {
        case .senseVoice:
            "SenseVoice"
        case .funASRRealtime:
            "FunASR Realtime"
        }
    }

    var isLocal: Bool {
        self != .funASRRealtime
    }

    static var localEngines: [Self] {
        allCases.filter(\.isLocal)
    }
}

@MainActor
final class MobileDictationSettingsStore: ObservableObject {
    @Published var selectedEngine: MobileDictationEngine {
        didSet {
            defaults.set(selectedEngine.rawValue, forKey: Self.selectedEngineKey)
        }
    }

    private static let selectedEngineKey = "dictation.engine"
    private static let legacySelectedModelKey = "dictation.localModel"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let rawValue = defaults.string(forKey: Self.selectedEngineKey),
            let engine = MobileDictationEngine(rawValue: rawValue)
        {
            selectedEngine = engine
        } else if let legacyRawValue = defaults.string(forKey: Self.legacySelectedModelKey),
            let legacyEngine = MobileDictationEngine(rawValue: legacyRawValue),
            legacyEngine.isLocal
        {
            selectedEngine = legacyEngine
            defaults.set(legacyEngine.rawValue, forKey: Self.selectedEngineKey)
        } else {
            selectedEngine = .senseVoice
            defaults.set(selectedEngine.rawValue, forKey: Self.selectedEngineKey)
        }
    }
}

enum RetiredDictationModelCleanup {
    static func removeWhisperModel(
        from applicationSupportDirectory: URL? = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first,
        fileManager: FileManager = .default
    ) {
        guard let applicationSupportDirectory else { return }
        let modelDirectory =
            applicationSupportDirectory
            .appendingPathComponent("Stet", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("Whisper", isDirectory: true)
        guard fileManager.fileExists(atPath: modelDirectory.path) else { return }
        try? fileManager.removeItem(at: modelDirectory)
    }
}

protocol LocalDictationModelManaging {
    func status() async -> ASRModelStatus
    func download() async throws
    func delete() async throws
}

struct SenseVoiceLocalDictationModelManager: LocalDictationModelManaging {
    let modelManager: SenseVoiceModelManager

    func status() async -> ASRModelStatus {
        await modelManager.status(for: SenseVoiceModelManager.modelName)
    }

    func download() async throws {
        try await modelManager.downloadIfNeeded(for: SenseVoiceModelManager.modelName)
    }

    func delete() async throws {
        try await modelManager.deleteModel(for: SenseVoiceModelManager.modelName)
    }
}

struct UnavailableLocalDictationModelManager: LocalDictationModelManaging {
    let currentStatus: ASRModelStatus

    func status() async -> ASRModelStatus {
        currentStatus
    }

    func download() async throws {
        throw LocalDictationModelManagerError.unavailable
    }

    func delete() async throws {
        throw LocalDictationModelManagerError.unavailable
    }
}

private enum LocalDictationModelManagerError: Error {
    case unavailable
}
