#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @Suite("Retired Local Whisper Cleanup")
    struct RetiredLocalWhisperCleanupTests {
        @Test func removesDefaultModelFilesAndClearsPreference() throws {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("stet-retired-whisper-\(UUID().uuidString)", isDirectory: true)
            let models =
                root
                .appendingPathComponent("Stet", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
            try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
            let modelURL = models.appendingPathComponent(RetiredLocalWhisperCleanup.defaultModelFileName)
            let encoderURL = models.appendingPathComponent(RetiredLocalWhisperCleanup.defaultEncoderDirectoryName)
            try Data("model".utf8).write(to: modelURL)
            try FileManager.default.createDirectory(at: encoderURL, withIntermediateDirectories: true)
            let parakeet = models.appendingPathComponent("parakeet.keep")
            try Data("keep".utf8).write(to: parakeet)

            let defaults = TestSupport.makeUserDefaults()
            defaults.set("/tmp/custom-whisper.bin", forKey: MacPreferences.localWhisperModelPath)

            RetiredLocalWhisperCleanup.removeInstalledAssets(
                from: root,
                defaults: defaults
            )

            #expect(!FileManager.default.fileExists(atPath: modelURL.path))
            #expect(!FileManager.default.fileExists(atPath: encoderURL.path))
            #expect(FileManager.default.fileExists(atPath: parakeet.path))
            #expect(defaults.object(forKey: MacPreferences.localWhisperModelPath) == nil)

            try? FileManager.default.removeItem(at: root)
        }
    }
#endif
