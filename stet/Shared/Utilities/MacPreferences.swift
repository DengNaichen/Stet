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

    nonisolated static let localWhisperModelPath = "mac.localWhisperModelPath"

    /// BCP-47 code for the primary dictation language.
    nonisolated static let transcriptionPrimaryLanguage = "mac.transcriptionPrimaryLanguage"

    /// BCP-47 code for the secondary dictation language, if any.
    nonisolated static let transcriptionSecondaryLanguage = "mac.transcriptionSecondaryLanguage"

    /// Which on-device transcription engine the dictation pipeline uses.
    /// Values are `StoredTranscriptionEngine.rawValue` ("fluidAudio" or "localWhisper").
    nonisolated static let transcriptionEngine = "mac.transcriptionEngine"
}

enum StoredTranscriptionEngine: String, CaseIterable, Sendable {
    case fluidAudio
    case localWhisper

    nonisolated static let `default`: StoredTranscriptionEngine = .localWhisper

    nonisolated static func current(defaults: UserDefaults = .standard) -> StoredTranscriptionEngine {
        guard let raw = defaults.string(forKey: MacPreferences.transcriptionEngine) else {
            return .default
        }
        return StoredTranscriptionEngine(rawValue: raw) ?? .default
    }
}

enum TranscriptionEngine: Equatable, Sendable {
    case fluidAudio
    case localWhisper(languageHint: String?)
}
