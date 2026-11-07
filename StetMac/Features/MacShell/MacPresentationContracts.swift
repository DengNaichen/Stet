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
        var meteringUpdates: AnyPublisher<Void, Never> { get }
        var dictationState: DictationState { get }
        var statusText: String { get }
        var recordingLevel: Double { get }
        var audioFeatures: MacDictationCapsuleVisualSignals { get }
        var detectedTargetApplication: AppInfo? { get }
        func hidePanel()
        func dismissPendingCopy()
        func cancelActiveCapture()
        func performPrimaryAction()
    }

    extension MacDictationPanelCoordinating {
        var meteringUpdates: AnyPublisher<Void, Never> {
            Empty().eraseToAnyPublisher()
        }
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
        func finishOnboarding()
    }

    extension MacPermissionsCoordinating {
        var onboardingStep: MacOnboardingStep { .done }
        var onboardingMode: MacOnboardingMode? { nil }
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
        func finishOnboarding() {}
    }

    @MainActor
    protocol MacSettingsShellCoordinating: AnyObject, MacGeneralSettingsAppModeling, MacMCPSettingsAppModeling {
        func openSettings(using action: () -> Void)
        func settingsDidAppear()
        func settingsDidDisappear()
    }

    @MainActor
    protocol MacAppPresentationModeling: MacDictationPanelCoordinating, MacPermissionsCoordinating {}

    enum MacAppUpdateState: Equatable {
        case unavailable(String)
        case idle
        case checking
        case upToDate(version: String)
        case updateAvailable(currentVersion: String, latestVersion: String)
        case failed(String)
    }

    /// Publishers deliver the new value synchronously on MainActor, including the initial snapshot.
    @MainActor
    protocol MacAppUpdateCoordinating: AnyObject {
        var updateSnapshot: MacAppUpdateSnapshot { get }
        var updateSnapshots: AnyPublisher<MacAppUpdateSnapshot, Never> { get }
        func checkForUpdates()
        func setAutomaticallyChecksForUpdates(_ enabled: Bool)
    }

    @MainActor
    protocol MacMeetingCoordinating: MacCalendarSettingsAppModeling {
        var meetingSpeakerSettings: MeetingSpeakerSettings { get }
        var meetingSnapshot: MacMeetingSnapshot { get }
        var meetingSnapshots: AnyPublisher<MacMeetingSnapshot, Never> { get }
        func toggleMeetingRecording()
    }
#endif
