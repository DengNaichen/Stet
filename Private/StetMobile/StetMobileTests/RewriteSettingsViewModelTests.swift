import Foundation
import Testing
@testable import StetMobile

struct RewriteSettingsViewModelTests {
    @MainActor
    @Test func dictationEngineIsRealtimeOnly() {
        let suiteName = "MobileDictationSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("senseVoice", forKey: "dictation.engine")

        #expect(MobileDictationEngine.allCases == [.funASRRealtime])
        #expect(MobileDictationSettingsStore(defaults: defaults).selectedEngine == .funASRRealtime)
        #expect(defaults.string(forKey: "dictation.engine") == "funASRRealtime")
    }

    @MainActor
    @Test func retiredWhisperModelIsRemoved() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StetRetiredModelCleanupTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let modelDirectory =
            directory
            .appendingPathComponent("Stet", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("Whisper", isDirectory: true)
        try FileManager.default.createDirectory(
            at: modelDirectory,
            withIntermediateDirectories: true
        )
        let modelURL = modelDirectory.appendingPathComponent("model.bin")
        try Data([1]).write(to: modelURL)

        RetiredDictationModelCleanup.removeWhisperModel(
            from: directory,
            fileManager: .default
        )

        #expect(!FileManager.default.fileExists(atPath: modelDirectory.path))
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }
}
