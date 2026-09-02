#if os(macOS)
    import AppKit
    import Combine
    import Foundation
    import os
    import StetVisuals

    @MainActor
    final class MacAppSessionController {
        static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
            category: "perfTrace"
        )
        static let permissionsLogger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
            category: "permissions"
        )
        typealias PrimaryActionSource = MacDictationWorkflowController.PrimaryActionSource

        var onChange: (() -> Void)?

        let workflowController: MacDictationWorkflowController
        let shellPresentationController: any MacShellPresenting
        let permissionGateController: any MacPermissionGatePresenting
        let onboardingWindowController: MacOnboardingWindowController
        let permissionManager: MacPermissionManager
        let pipelineFactory: DictationPipelineFactory
        let appBranchMonitor: AppBranchMonitor
        let defaults: UserDefaults
        let notificationCenter: NotificationCenter
        let hotkeyRegistrar: any MacDictationHotkeyRegistering
        var isMeetingSessionBusy: () -> Bool = { false }
        var onMeetingHotkey: () -> Void = {}
        var cancellables = Set<AnyCancellable>()
        var completionHandlingTask: Task<Void, Never>?
        var hotkeyInteraction = MacDictationHotkeyInteraction()
        var previousDictationState: DictationState = .idle
        weak var presentationModel: (any MacAppPresentationModeling)?
        var onboardingStepState: MacOnboardingStep
        var onboardingModeState: MacOnboardingMode?
        var onboardingAppearanceThemeState: MacDictationVisualTheme
        var hasAppliedOnboardingAppearanceTheme = false
        var shortcutTestDetectedPressState = false
        var shortcutTestCompletedRoundTripState = false
        var shortcutTestPreviewTextState: String?
        var firstSuccessPreviewTextState: String?
        var firstSuccessFailureMessageState: String?
        var firstSuccessFailureCount = 0
        var detectedTargetApplicationState: AppInfo?
        var appBranchObserverID: UUID?
        var appLifecycleState = "active"

        init(
            workflowController: MacDictationWorkflowController,
            shellPresentationController: any MacShellPresenting,
            permissionGateController: any MacPermissionGatePresenting,
            onboardingWindowController: MacOnboardingWindowController,
            permissionManager: MacPermissionManager,
            pipelineFactory: DictationPipelineFactory,
            appBranchMonitor: AppBranchMonitor = .shared,
            defaults: UserDefaults = .standard,
            notificationCenter: NotificationCenter = .default,
            hotkeyRegistrar: any MacDictationHotkeyRegistering
        ) {
            self.workflowController = workflowController
            self.shellPresentationController = shellPresentationController
            self.permissionGateController = permissionGateController
            self.onboardingWindowController = onboardingWindowController
            self.permissionManager = permissionManager
            self.pipelineFactory = pipelineFactory
            self.appBranchMonitor = appBranchMonitor
            self.defaults = defaults
            self.notificationCenter = notificationCenter
            self.hotkeyRegistrar = hotkeyRegistrar
            self.onboardingStepState = .done
            self.onboardingAppearanceThemeState = .egg
            self.hasAppliedOnboardingAppearanceTheme = false

            configure()
        }

        deinit {
            if let appBranchObserverID {
                appBranchMonitor.removeObserver(appBranchObserverID)
            }
        }

        convenience init(
            workflowController: MacDictationWorkflowController,
            permissionManager: MacPermissionManager,
            pipelineFactory: DictationPipelineFactory,
            appBranchMonitor: AppBranchMonitor = .shared,
            defaults: UserDefaults = .standard,
            notificationCenter: NotificationCenter = .default
        ) {
            self.init(
                workflowController: workflowController,
                shellPresentationController: MacShellPresentationController(),
                permissionGateController: MacPermissionGateController(),
                onboardingWindowController: MacOnboardingWindowController(),
                permissionManager: permissionManager,
                pipelineFactory: pipelineFactory,
                appBranchMonitor: appBranchMonitor,
                defaults: defaults,
                notificationCenter: notificationCenter,
                hotkeyRegistrar: KeyboardShortcutsHotkeyRegistrar()
            )
        }

        @available(
            *, deprecated,
            message:
                "Use the designated initializer with non-optional dependencies or the convenience initializer without dependencies."
        )
        convenience init(
            workflowController: MacDictationWorkflowController,
            shellPresentationController: (any MacShellPresenting)? = nil,
            permissionGateController: (any MacPermissionGatePresenting)? = nil,
            onboardingWindowController: MacOnboardingWindowController? = nil,
            permissionManager: MacPermissionManager,
            pipelineFactory: DictationPipelineFactory,
            appBranchMonitor: AppBranchMonitor = .shared,
            defaults: UserDefaults = .standard,
            notificationCenter: NotificationCenter = .default,
            hotkeyRegistrar: (any MacDictationHotkeyRegistering)? = nil
        ) {
            self.init(
                workflowController: workflowController,
                shellPresentationController: shellPresentationController ?? MacShellPresentationController(),
                permissionGateController: permissionGateController ?? MacPermissionGateController(),
                onboardingWindowController: onboardingWindowController ?? MacOnboardingWindowController(),
                permissionManager: permissionManager,
                pipelineFactory: pipelineFactory,
                appBranchMonitor: appBranchMonitor,
                defaults: defaults,
                notificationCenter: notificationCenter,
                hotkeyRegistrar: hotkeyRegistrar ?? KeyboardShortcutsHotkeyRegistrar()
            )
        }

        func configure() {
            workflowController.dictationViewModel.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.notifyChange()
                }
                .store(in: &cancellables)

            shellPresentationController.onVisibilityChange = { [weak self] in
                self?.notifyChange()
            }

            configureAppBranchMonitoring()
            bindState()
            bindLifecycleNotifications()
            registerHotkeys()
        }

        var dictationState: DictationState {
            workflowController.dictationViewModel.state
        }

        var statusText: String {
            workflowController.statusText
        }

        var processingStatusText: String {
            workflowController.processingStatusText
        }

        var recordingLevel: Double {
            workflowController.dictationViewModel.recordingLevel
        }

        var audioFeatures: MacDictationCapsuleVisualSignals {
            workflowController.dictationViewModel.audioFeatures
        }

        var detectedTargetApplication: AppInfo? {
            detectedTargetApplicationState
        }

        var isPanelVisible: Bool {
            shellPresentationController.isPanelVisible
        }

        var hasRequiredPermissions: Bool {
            permissionManager.hasRequiredPermissions
        }

        var autoPasteStatusText: String {
            permissionManager.autoPasteStatusText
        }

        var speechRecognitionStatusText: String {
            permissionManager.speechRecognitionStatusText
        }

        var microphoneAccessStatusText: String {
            permissionManager.microphoneAccessStatusText
        }

        var microphoneAccessNeedsAttention: Bool {
            permissionManager.microphoneAccessNeedsAttention
        }

        var microphonePermissionActionTitle: String {
            permissionManager.microphonePermissionActionTitle
        }

        var autoPasteAccessNeedsAttention: Bool {
            permissionManager.autoPasteAccessNeedsAttention
        }

        var onboardingStep: MacOnboardingStep {
            requiresOnboarding ? onboardingStepState : .done
        }

        var onboardingMode: MacOnboardingMode? {
            onboardingModeState
        }

        var shortcutTestDetectedPress: Bool {
            shortcutTestDetectedPressState
        }

        var shortcutTestCompletedRoundTrip: Bool {
            shortcutTestCompletedRoundTripState
        }

        var shortcutTestPreviewText: String? {
            shortcutTestPreviewTextState
        }

        var canContinueShortcutOnboarding: Bool {
            shortcutTestDetectedPressState
                && shortcutTestCompletedRoundTripState
                && !(shortcutTestPreviewTextState?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }

        var firstSuccessPreviewText: String? {
            firstSuccessPreviewTextState
        }

        var firstSuccessFailureMessage: String? {
            firstSuccessFailureMessageState
        }

        var canContinueFirstSuccessOnboarding: Bool {
            !(firstSuccessPreviewTextState?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }

        var canSkipFirstSuccessOnboarding: Bool {
            firstSuccessFailureCount >= 2
        }

        var canFinishAppearanceOnboarding: Bool {
            hasAppliedOnboardingAppearanceTheme
        }

        var currentShowInDockPreference: Bool {
            defaults.object(forKey: MacPreferences.showInDock) as? Bool ?? false
        }

        var requiresOnboarding: Bool {
            isDebugForceOnboardingEnabled || !defaults.bool(forKey: MacPreferences.onboardingCompleted)
        }

        var shouldPresentOnboardingGate: Bool {
            requiresOnboarding && !onboardingStepState.allowsAudioCapture
        }

        var shouldPresentRuntimePermissionFailureWindow: Bool {
            !hasRequiredPermissions
        }

        var shouldPresentPermissionGate: Bool {
            shouldPresentOnboardingGate || shouldPresentRuntimePermissionFailureWindow
        }

        var isDebugForceOnboardingEnabled: Bool {
            if defaults.bool(forKey: MacPreferences.debugForceOnboarding) {
                return true
            }

            if ProcessInfo.processInfo.arguments.contains("--force-onboarding") {
                return true
            }

            guard let value = ProcessInfo.processInfo.environment["STET_FORCE_ONBOARDING"] else {
                return false
            }

            return ["1", "true", "yes", "on"].contains(value.lowercased())
        }
    }
#endif
