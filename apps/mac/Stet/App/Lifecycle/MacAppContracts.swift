#if os(macOS)
import Combine
import Foundation

enum MacOnboardingMode: String, Sendable {
    case apiKey
    case managed
}

enum MacOnboardingStep: Int, CaseIterable, Sendable {
    case welcome = 1
    case mode
    case apiKey
    case login
    case permissions
    case shortcut
    case firstSuccess
    case done

    var progressIndex: Int {
        switch self {
        case .welcome:
            return 1
        case .mode:
            return 2
        case .apiKey, .login:
            return 3
        case .permissions:
            return 4
        case .shortcut:
            return 5
        case .firstSuccess:
            return 6
        case .done:
            return 7
        }
    }

    var allowsAudioCapture: Bool {
        switch self {
        case .shortcut, .firstSuccess:
            return true
        case .welcome, .mode, .apiKey, .login, .permissions, .done:
            return false
        }
    }
}

@MainActor
protocol MacAppStatusObserving: AnyObject {
    var updates: AnyPublisher<Void, Never> { get }
}

@MainActor
protocol MacDictationCommandsCoordinating: MacAppStatusObserving {
    var menuBarSymbolName: String { get }
    var primaryButtonTitle: String { get }
    var panelButtonTitle: String { get }
    func performPrimaryAction()
    func togglePanel()
}

@MainActor
protocol MacDictationPanelCoordinating: MacAppStatusObserving {
    var dictationState: DictationState { get }
    var statusText: String { get }
    var recordingLevel: Double { get }
    func hidePanel()
    func dismissPendingCopy()
    func cancelActiveCapture()
    func performPrimaryAction()
}

@MainActor
protocol MacPermissionsCoordinating: MacAppStatusObserving {
    var autoPasteStatusText: String { get }
    var microphoneAccessStatusText: String { get }
    var microphoneAccessNeedsAttention: Bool { get }
    var microphonePermissionActionTitle: String { get }
    var autoPasteAccessNeedsAttention: Bool { get }
    var onboardingStep: MacOnboardingStep { get }
    var onboardingMode: MacOnboardingMode? { get }
    var relaySessionEmail: String? { get }
    var shortcutTestDetectedPress: Bool { get }
    var shortcutTestCompletedRoundTrip: Bool { get }
    var shortcutTestPreviewText: String? { get }
    var canContinueShortcutOnboarding: Bool { get }
    var firstSuccessPreviewText: String? { get }
    var firstSuccessFailureMessage: String? { get }
    var canContinueFirstSuccessOnboarding: Bool { get }
    var canSkipFirstSuccessOnboarding: Bool { get }
    func requestAutoPasteAccess()
    func resolveMicrophoneAccess()
    func openAccessibilitySettings()
    func chooseOnboardingMode(_ mode: MacOnboardingMode)
    func advanceOnboarding()
    func retreatOnboarding()
    func completeAPIKeyOnboarding(provider: DictationProvider)
    func completeManagedOnboarding()
    func finishOnboarding()
}

extension MacPermissionsCoordinating {
    var onboardingStep: MacOnboardingStep { .permissions }
    var onboardingMode: MacOnboardingMode? { nil }
    var relaySessionEmail: String? { nil }
    var shortcutTestDetectedPress: Bool { false }
    var shortcutTestCompletedRoundTrip: Bool { false }
    var shortcutTestPreviewText: String? { nil }
    var canContinueShortcutOnboarding: Bool { false }
    var firstSuccessPreviewText: String? { nil }
    var firstSuccessFailureMessage: String? { nil }
    var canContinueFirstSuccessOnboarding: Bool { false }
    var canSkipFirstSuccessOnboarding: Bool { false }

    func chooseOnboardingMode(_ mode: MacOnboardingMode) {}
    func advanceOnboarding() {}
    func retreatOnboarding() {}
    func completeAPIKeyOnboarding(provider: DictationProvider) {}
    func completeManagedOnboarding() {}
    func finishOnboarding() {}
}

@MainActor
protocol MacSettingsShellCoordinating: AnyObject, MacGeneralSettingsAppModeling {
    func openSettings(using action: () -> Void)
    func settingsDidAppear()
    func settingsDidDisappear()
}

@MainActor
protocol MacAppPresentationModeling: MacDictationPanelCoordinating, MacPermissionsCoordinating {}

@MainActor
protocol MacShellPresenting: AnyObject {
    var onVisibilityChange: (() -> Void)? { get set }
    var isPanelVisible: Bool { get }
    func showPanel(appModel: any MacDictationPanelCoordinating)
    func showTransientPanel(appModel: any MacDictationPanelCoordinating)
    func hidePanel()
    func togglePanel(appModel: any MacDictationPanelCoordinating)
    func panelDidHide()
    func cancelScheduledPanelHide()
    func scheduleTransientPanelHideIfNeeded(currentState: @escaping @MainActor () -> DictationState)
    func applyDockVisibility(showInDock: Bool)
    func openSettings(currentShowInDockPreference: Bool, using action: () -> Void)
    func settingsDidAppear(currentShowInDockPreference: Bool)
    func settingsDidDisappear(currentShowInDockPreference: Bool)
}

@MainActor
protocol MacPermissionGatePresenting: AnyObject {
    func show(appModel: any MacPermissionsCoordinating)
    func hide()
}

@MainActor
protocol MacDictationHotkeyRegistering {
    func clearDictationHandlers()
    func registerDictationKeyDown(_ handler: @escaping () -> Void)
    func registerDictationKeyUp(_ handler: @escaping () -> Void)
}
#endif
