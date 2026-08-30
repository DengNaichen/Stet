import Foundation
import StetCore

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

    nonisolated var transcriptionEngine: StoredTranscriptionEngine {
        if let raw = defaults.string(forKey: MacPreferences.transcriptionEngine),
            let engine = StoredTranscriptionEngine(rawValue: raw)
        {
            return engine
        }
        defaults.set(StoredTranscriptionEngine.default.rawValue, forKey: MacPreferences.transcriptionEngine)
        return .default
    }

    nonisolated func saveTranscriptionEngine(_ engine: StoredTranscriptionEngine) {
        defaults.set(engine.rawValue, forKey: MacPreferences.transcriptionEngine)
    }
}
