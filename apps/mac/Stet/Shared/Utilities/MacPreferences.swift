import Foundation

enum MacPreferences {
    nonisolated static let onboardingCompleted = "mac.onboardingCompleted"
    nonisolated static let debugForceOnboarding = "mac.debug.forceOnboarding"
    nonisolated static let pauseMediaDuringDictation = "mac.pauseMediaDuringDictation"
    nonisolated static let transcriptionProvider = "mac.transcriptionProvider"
    nonisolated static let rewriteProvider = "mac.rewriteProvider"
    nonisolated static let aiExecutionMode = "mac.aiExecutionMode"
    nonisolated static let rewriteEnabled = "mac.rewriteEnabled"
    nonisolated static let dictationLanguageMode = "mac.dictationLanguageMode"
    nonisolated static let globalHotkeyShortcut = "mac.globalHotkeyShortcut"
    nonisolated static let togglePanelHotkeyShortcut = "mac.togglePanelHotkeyShortcut"
    nonisolated static let rewriteHotkeyShortcut = "mac.rewriteHotkeyShortcut"
    nonisolated static let hotkeyPreset = "mac.hotkeyPreset"
    nonisolated static let hotkeyDistinguishModifierSides = "mac.hotkeyDistinguishModifierSides"
    nonisolated static let dictationPerfTracingEnabled = "mac.dictationPerfTracingEnabled"
    nonisolated static let personalDictionary = "mac.personalDictionary"
    nonisolated static let personalDictionaryEnabled = "mac.personalDictionaryEnabled"
    nonisolated static let interactionSoundsEnabled = "mac.interactionSoundsEnabled"
    nonisolated static let interactionSoundPreset = "mac.interactionSoundPreset"
    nonisolated static let shaderTheme = "mac.shaderTheme"
    nonisolated static let launchAtLogin = "mac.launchAtLogin"
    nonisolated static let showInDock = "mac.showInDock"
    
    // Audio device selection
    nonisolated static let preferredAudioInputDeviceUID = "mac.preferredAudioInputDeviceUID"
}
