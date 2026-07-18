import Foundation

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
