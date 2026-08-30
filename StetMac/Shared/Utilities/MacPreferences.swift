import Foundation
import StetCore

enum MacPreferences {
    nonisolated static let onboardingCompleted = "mac.onboardingCompleted"
    nonisolated static let debugForceOnboarding = "mac.debug.forceOnboarding"
    nonisolated static let pauseMediaDuringDictation = "mac.pauseMediaDuringDictation"
    nonisolated static let transcriptionProvider = "mac.transcriptionProvider"
    nonisolated static let rewriteProvider = "mac.rewriteProvider"
    nonisolated static let rewriteEnabled = "mac.rewriteEnabled"
    nonisolated static let customRewriteModel = "mac.customRewriteModel"
    nonisolated static let dictationLanguageMode = "mac.dictationLanguageMode"
    nonisolated static let globalHotkeyShortcut = "mac.globalHotkeyShortcut"
    nonisolated static let togglePanelHotkeyShortcut = "mac.togglePanelHotkeyShortcut"
    nonisolated static let rewriteHotkeyShortcut = "mac.rewriteHotkeyShortcut"
    nonisolated static let hotkeyPreset = "mac.hotkeyPreset"
    nonisolated static let hotkeyDistinguishModifierSides = "mac.hotkeyDistinguishModifierSides"
    nonisolated static let dictationPerfTracingEnabled = "mac.dictationPerfTracingEnabled"
    nonisolated static let dictationTranscriptTracingEnabled = "mac.dictationTranscriptTracingEnabled"
    nonisolated static let mcpServerEnabled = "mac.mcpServerEnabled"
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

    nonisolated static let senseVoiceModelPath = "mac.senseVoiceModelPath"

    /// BCP-47 code for the primary dictation language.
    nonisolated static let transcriptionPrimaryLanguage = "mac.transcriptionPrimaryLanguage"

    /// BCP-47 code for the secondary dictation language, if any.
    nonisolated static let transcriptionSecondaryLanguage = "mac.transcriptionSecondaryLanguage"

    /// Which on-device transcription engine the dictation pipeline uses.
    /// Values are `StoredTranscriptionEngine.rawValue`.
    nonisolated static let transcriptionEngine = "mac.transcriptionEngine"
}
