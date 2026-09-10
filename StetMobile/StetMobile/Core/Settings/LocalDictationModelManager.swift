import Combine
import Foundation

enum MobileDictationEngine: String, CaseIterable, Identifiable, Sendable {
    case funASRRealtime

    var id: Self { self }

    var displayName: String {
        "FunASR Realtime"
    }
}

@MainActor
final class MobileDictationSettingsStore: ObservableObject {
    @Published var selectedEngine: MobileDictationEngine {
        didSet {
            defaults.set(selectedEngine.rawValue, forKey: Self.selectedEngineKey)
        }
    }

    private static let selectedEngineKey = "dictation.engine"
    private static let legacySelectedModelKey = "dictation.localModel"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedEngine = .funASRRealtime
        defaults.set(selectedEngine.rawValue, forKey: Self.selectedEngineKey)
        defaults.removeObject(forKey: Self.legacySelectedModelKey)
    }
}

enum RetiredDictationModelCleanup {
    static func removeWhisperModel(
        from applicationSupportDirectory: URL? = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first,
        fileManager: FileManager = .default
    ) {
        guard let applicationSupportDirectory else { return }
        let modelDirectory =
            applicationSupportDirectory
            .appendingPathComponent("Stet", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("Whisper", isDirectory: true)
        guard fileManager.fileExists(atPath: modelDirectory.path) else { return }
        try? fileManager.removeItem(at: modelDirectory)
    }
}
