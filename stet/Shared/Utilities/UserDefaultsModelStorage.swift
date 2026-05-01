import Foundation

struct UserDefaultsModelStorage: ModelStorageConfiguration {
    private let defaults: UserDefaults

    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    nonisolated var localWhisperModelPath: String? {
        defaults.string(forKey: MacPreferences.localWhisperModelPath)
    }

    nonisolated func saveLocalWhisperModelPath(_ path: String?) {
        if let path {
            defaults.set(path, forKey: MacPreferences.localWhisperModelPath)
        } else {
            defaults.removeObject(forKey: MacPreferences.localWhisperModelPath)
        }
    }

    nonisolated var sherpaOnnxSenseVoiceModelPath: String? {
        defaults.string(forKey: MacPreferences.sherpaOnnxSenseVoiceModelPath)
    }

    nonisolated func saveSherpaOnnxSenseVoiceModelPath(_ path: String?) {
        if let path {
            defaults.set(path, forKey: MacPreferences.sherpaOnnxSenseVoiceModelPath)
        } else {
            defaults.removeObject(forKey: MacPreferences.sherpaOnnxSenseVoiceModelPath)
        }
    }

    nonisolated var transcriptionEngine: StoredTranscriptionEngine {
        guard let raw = defaults.string(forKey: MacPreferences.transcriptionEngine) else {
            return .default
        }
        return StoredTranscriptionEngine(rawValue: raw) ?? .default
    }

    nonisolated func saveTranscriptionEngine(_ engine: StoredTranscriptionEngine) {
        defaults.set(engine.rawValue, forKey: MacPreferences.transcriptionEngine)
    }
}
