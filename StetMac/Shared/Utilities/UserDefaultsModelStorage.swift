import Foundation
import StetCore

struct UserDefaultsModelStorage: ModelStorageConfiguration {
    private let defaults: UserDefaults

    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
