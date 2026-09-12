import Foundation

/// Deletes leftover Whisper.cpp model files and the retired custom-path preference.
enum RetiredLocalWhisperCleanup {
    static let defaultModelFileName = "ggml-large-v3-turbo-q5_0.bin"
    static let defaultEncoderDirectoryName = "ggml-large-v3-turbo-encoder.mlmodelc"
    static let preferenceKey = MacPreferences.localWhisperModelPath

    static func removeInstalledAssets(
        from applicationSupportDirectory: URL? = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        defaults.removeObject(forKey: preferenceKey)
        guard let applicationSupportDirectory else { return }
        let modelsDirectory =
            applicationSupportDirectory
            .appendingPathComponent("Stet", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try? fileManager.removeItem(at: modelsDirectory.appendingPathComponent(defaultModelFileName))
        try? fileManager.removeItem(at: modelsDirectory.appendingPathComponent(defaultEncoderDirectoryName))
    }
}
