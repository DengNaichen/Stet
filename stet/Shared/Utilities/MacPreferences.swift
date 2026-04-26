import Foundation

enum MacPreferences {
    nonisolated static let onboardingCompleted = "mac.onboardingCompleted"
    nonisolated static let debugForceOnboarding = "mac.debug.forceOnboarding"
    nonisolated static let pauseMediaDuringDictation = "mac.pauseMediaDuringDictation"
    nonisolated static let transcriptionProvider = "mac.transcriptionProvider"
    nonisolated static let rewriteProvider = "mac.rewriteProvider"
    nonisolated static let rewriteEnabled = "mac.rewriteEnabled"
    nonisolated static let dictationLanguageMode = "mac.dictationLanguageMode"
    nonisolated static let globalHotkeyShortcut = "mac.globalHotkeyShortcut"
    nonisolated static let togglePanelHotkeyShortcut = "mac.togglePanelHotkeyShortcut"
    nonisolated static let rewriteHotkeyShortcut = "mac.rewriteHotkeyShortcut"
    nonisolated static let hotkeyPreset = "mac.hotkeyPreset"
    nonisolated static let hotkeyDistinguishModifierSides = "mac.hotkeyDistinguishModifierSides"
    nonisolated static let dictationPerfTracingEnabled = "mac.dictationPerfTracingEnabled"
    nonisolated static let dictationTranscriptTracingEnabled = "mac.dictationTranscriptTracingEnabled"
    nonisolated static let personalDictionary = "mac.personalDictionary"
    nonisolated static let personalDictionaryEnabled = "mac.personalDictionaryEnabled"
    nonisolated static let interactionSoundsEnabled = "mac.interactionSoundsEnabled"
    nonisolated static let interactionSoundPreset = "mac.interactionSoundPreset"
    nonisolated static let shaderTheme = "mac.shaderTheme"
    nonisolated static let launchAtLogin = "mac.launchAtLogin"
    nonisolated static let showInDock = "mac.showInDock"

    // Audio device selection
    nonisolated static let preferredAudioInputDeviceUID = "mac.preferredAudioInputDeviceUID"

    // Local Whisper model override
    nonisolated static let localWhisperModelPath = "mac.localWhisperModelPath"

    /// Which on-device transcription engine the dictation pipeline uses.
    /// Values are `LocalTranscriptionEngine.rawValue` ("whisper" or "parakeet").
    /// Missing/unknown defaults to whisper.
    nonisolated static let localTranscriptionEngine = "mac.localTranscriptionEngine"
}

enum LocalTranscriptionEngine: String, CaseIterable, Sendable {
    case whisper
    case parakeet

    nonisolated static let `default`: LocalTranscriptionEngine = .whisper

    nonisolated static func current(defaults: UserDefaults = .standard) -> LocalTranscriptionEngine {
        guard let raw = defaults.string(forKey: MacPreferences.localTranscriptionEngine) else {
            return .default
        }
        return LocalTranscriptionEngine(rawValue: raw) ?? .default
    }

    nonisolated var displayName: String {
        switch self {
        case .whisper: return "Whisper (large-v3-turbo q5_0)"
        case .parakeet: return "Parakeet V3 (Multilingual)"
        }
    }
}
