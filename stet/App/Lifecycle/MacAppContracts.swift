#if os(macOS)
    import Combine
    import Foundation
    import StetVisuals

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
        var audioFeatures: MacDictationCapsuleVisualSignals { get }
        var detectedTargetApplication: AppInfo? { get }
        func hidePanel()
        func dismissPendingCopy()
        func cancelActiveCapture()
        func performPrimaryAction()
        func upgrade()
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
        var canFinishAppearanceOnboarding: Bool { get }
        func requestAutoPasteAccess()
        func resolveMicrophoneAccess()
        func openAccessibilitySettings()
        func chooseOnboardingMode(_ mode: MacOnboardingMode)
        func selectOnboardingAppearanceTheme(_ theme: MacDictationVisualTheme)
        func applyOnboardingAppearanceTheme()
        func advanceOnboarding()
        func retreatOnboarding()
        func completeAPIKeyOnboarding(provider: DictationProvider)
        func completeManagedOnboarding()
        func finishOnboarding()
    }

    extension MacPermissionsCoordinating {
        var onboardingStep: MacOnboardingStep { .done }
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
        var canFinishAppearanceOnboarding: Bool { false }

        func chooseOnboardingMode(_ mode: MacOnboardingMode) {}
        func selectOnboardingAppearanceTheme(_ theme: MacDictationVisualTheme) {}
        func applyOnboardingAppearanceTheme() {}
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

extension Notification.Name {
    static let stetBillingCompleted = Notification.Name("stetBillingCompleted")
}
