import FluidAudio
import Foundation

/// Manages the NVIDIA Parakeet V3 multilingual model via the FluidAudio SPM
/// package. Scope is intentionally narrow: a single hardcoded version (`v3`),
/// a download trigger, and a downloaded/not-downloaded status for the settings
/// UI. Mirrors the relevant slice of VoiceInk's `FluidAudioModelManager`.
struct FluidAudioModelManager: Sendable {
    nonisolated static let version: AsrModelVersion = .v3
    nonisolated static let displayName = "Parakeet V3 (Multilingual)"

    nonisolated init() {}

    nonisolated func isModelDownloaded() -> Bool {
        let cacheDirectory = AsrModels.defaultCacheDirectory(for: Self.version)
        return AsrModels.modelsExist(at: cacheDirectory, version: Self.version)
    }

    func downloadModel() async throws {
        _ = try await AsrModels.downloadAndLoad(version: Self.version)
    }

    nonisolated func cacheDirectoryURL() -> URL {
        AsrModels.defaultCacheDirectory(for: Self.version)
    }
}
