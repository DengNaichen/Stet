import Combine
import Foundation

enum MobileDictationModel: String, CaseIterable, Identifiable, Sendable {
    case senseVoice
    case whisperLargeV3Turbo

    var id: Self { self }

    var displayName: String {
        switch self {
        case .senseVoice:
            "SenseVoice"
        case .whisperLargeV3Turbo:
            "Whisper large-v3-turbo"
        }
    }
}

@MainActor
final class LocalDictationSettingsStore: ObservableObject {
    @Published var selectedModel: MobileDictationModel {
        didSet {
            defaults.set(selectedModel.rawValue, forKey: Self.selectedModelKey)
        }
    }

    private static let selectedModelKey = "dictation.localModel"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedModel =
            defaults.string(forKey: Self.selectedModelKey)
            .flatMap(MobileDictationModel.init(rawValue:))
            ?? .senseVoice
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

struct WhisperLocalDictationModelManager: LocalDictationModelManaging {
    let modelManager: WhisperModelManager

    func status() async -> ASRModelStatus {
        await modelManager.status(for: WhisperModelManager.modelName)
    }

    func download() async throws {
        try await modelManager.downloadIfNeeded(for: WhisperModelManager.modelName)
    }

    func delete() async throws {
        try await modelManager.deleteModel(for: WhisperModelManager.modelName)
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
