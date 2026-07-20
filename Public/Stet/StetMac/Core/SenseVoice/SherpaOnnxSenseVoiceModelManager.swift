import Foundation
import StetASR
import StetCore

/// macOS-facing convenience API for the shared SenseVoice model store.
///
/// This keeps existing settings and onboarding call sites small while ensuring
/// they use the exact same asset manifest and Application Support directory as
/// the iOS keyboard.
struct SherpaOnnxSenseVoiceModelManager: Sendable {
    nonisolated static let defaultModelFileName = SenseVoiceModelAsset.model.fileName
    nonisolated static let defaultTokensFileName = SenseVoiceModelAsset.tokens.fileName
    nonisolated static let displayName = "SenseVoice"

    nonisolated init(configuration _: any ModelStorageConfiguration = UserDefaultsModelStorage()) {}

    nonisolated func defaultModelURL() throws -> URL {
        try SenseVoiceModelManager.defaultModelsDirectory()
            .appendingPathComponent(SenseVoiceModelAsset.model.fileName, isDirectory: false)
    }

    nonisolated func defaultTokensURL() throws -> URL {
        try SenseVoiceModelManager.defaultModelsDirectory()
            .appendingPathComponent(SenseVoiceModelAsset.tokens.fileName, isDirectory: false)
    }

    nonisolated func isModelDownloaded() -> Bool {
        guard let directory = try? SenseVoiceModelManager.defaultModelsDirectory() else { return false }
        let fileManager = FileManager.default
        return SenseVoiceModelAsset.allCases.allSatisfy {
            fileManager.fileExists(atPath: directory.appendingPathComponent($0.fileName).path)
        }
    }

    nonisolated func statusMessage() -> String {
        if isModelDownloaded() {
            return "SenseVoice model is ready."
        }
        return "SenseVoice will download on demand."
    }

    nonisolated func needsAttention() -> Bool {
        !isModelDownloaded()
    }

    nonisolated func installDefaultModel(
        downloadProgress: @escaping @Sendable (Double, Int64, Int64) -> Void = { _, _, _ in }
    ) async throws {
        downloadProgress(0, 0, 0)
        let manager = try SenseVoiceModelManager()
        try await manager.downloadIfNeeded(for: SenseVoiceModelManager.modelName)
        downloadProgress(1, 0, 0)
    }
}
