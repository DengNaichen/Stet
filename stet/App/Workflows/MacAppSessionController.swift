#if os(macOS)
    import AppKit
    import Combine
    import Foundation
    import StetVisuals
    internal import Auth

    @MainActor
    final class MacAppSessionController {
        typealias PrimaryActionSource = MacDictationWorkflowController.PrimaryActionSource

        var onChange: (() -> Void)?

        private let workflowController: MacDictationWorkflowController
        private let shellPresentationController: any MacShellPresenting
        private let permissionGateController: any MacPermissionGatePresenting
        private let onboardingWindowController: MacOnboardingWindowController
        private let permissionManager: MacPermissionManager
        private let appBranchMonitor: AppBranchMonitor
        private let defaults: UserDefaults
        private let notificationCenter: NotificationCenter
        private let hotkeyRegistrar: any MacDictationHotkeyRegistering
        private var cancellables = Set<AnyCancellable>()
        private var completionHandlingTask: Task<Void, Never>?
        private var hotkeyInteraction = MacDictationHotkeyInteraction()
        private var previousDictationState: DictationState = .idle
        private weak var presentationModel: (any MacAppPresentationModeling)?
        private var onboardingStepState: MacOnboardingStep
        private var onboardingModeState: MacOnboardingMode?
        private var onboardingAppearanceThemeState: MacDictationVisualTheme
        private var hasAppliedOnboardingAppearanceTheme = false
        private var shortcutTestDetectedPressState = false
        private var shortcutTestCompletedRoundTripState = false
        private var shortcutTestPreviewTextState: String?
        private var firstSuccessPreviewTextState: String?
        private var firstSuccessFailureMessageState: String?
        private var firstSuccessFailureCount = 0
        private var detectedTargetApplicationState: AppInfo?
        private var appBranchObserverID: UUID?
        private var appLifecycleState = "active"

        init(
            workflowController: MacDictationWorkflowController,
            shellPresentationController: any MacShellPresenting,
            permissionGateController: any MacPermissionGatePresenting,
            onboardingWindowController: MacOnboardingWindowController,
            permissionManager: MacPermissionManager,
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

        // Convenience: default dependencies
        convenience init(
            workflowController: MacDictationWorkflowController,
            permissionManager: MacPermissionManager,
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
                appBranchMonitor: appBranchMonitor,
                defaults: defaults,
                notificationCenter: notificationCenter,
                hotkeyRegistrar: KeyboardShortcutsHotkeyRegistrar()
            )
        }

        // Backwards-compatible convenience initializer (deprecated)
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
                appBranchMonitor: appBranchMonitor,
                defaults: defaults,
                notificationCenter: notificationCenter,
                hotkeyRegistrar: hotkeyRegistrar ?? KeyboardShortcutsHotkeyRegistrar()
            )
        }

        private func configure() {
            workflowController.dictationViewModel.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.notifyChange()
                }
                .store(in: &cancellables)

            self.shellPresentationController.onVisibilityChange = { [weak self] in
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

        var relaySessionEmail: String? {
            SupabaseService.shared.currentSession?.user.email
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

        func activate(presentationModel: any MacAppPresentationModeling, showInDock: Bool) {
            self.presentationModel = presentationModel
            applyDockVisibility(showInDock: showInDock)

            DispatchQueue.main.async { [weak self] in
                self?.resetOnboardingProgressIfNeeded()
                self?.refreshPermissionIndicators()
                self?.prewarmAudioEngine()
            }
        }

        private func prewarmAudioEngine() {
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                AppLogger.info("Pre-warming audio engine on activation", category: .dictation)
                await workflowController.prewarm()
            }
        }

        private func configureAppBranchMonitoring() {
            guard appBranchObserverID == nil else { return }

            appBranchMonitor.setExcludedBundleID(Bundle.main.bundleIdentifier)
            detectedTargetApplicationState = appBranchMonitor.currentApp
            appBranchObserverID = appBranchMonitor.addObserver { [weak self] appInfo in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.detectedTargetApplicationState = appInfo
                    self.notifyChange()
                }
            }
            appBranchMonitor.startMonitoring()
        }

        func performPrimaryAction() {
            performPrimaryAction(source: .interface)
        }

        func cancelActiveCapture() {
            hotkeyInteraction.reset()
            workflowController.cancelActiveCapture()
            hidePanel()
        }

        func requestAutoPasteAccess() {
            permissionManager.requestAutoPasteAccess()
            refreshPermissionIndicators()
        }

        func resolveMicrophoneAccess() {
            if permissionManager.microphoneAccessStatus.canRequestInApp {
                requestMicrophoneAccess()
            } else {
                openMicrophoneSettings()
            }
        }

        func openAccessibilitySettings() {
            permissionManager.openAccessibilitySettings()
        }

        func openMicrophoneSettings() {
            permissionManager.openMicrophoneSettings()
        }

        func showPanel() {
            guard !requiresOnboarding || onboardingStepState.allowsAudioCapture else {
                presentRequiredPermissionsGateIfNeeded()
                return
            }

            guard hasRequiredPermissions else {
                presentRequiredPermissionsGateIfNeeded()
                return
            }

            guard let presentationModel else { return }
            shellPresentationController.showPanel(appModel: presentationModel)
        }

        func hidePanel() {
            Task {
                await DictationRuntimeProbe.shared.markPanelHidden()
            }
            shellPresentationController.hidePanel()
        }

        func dismissPendingCopy() {
            Task {
                await DictationRuntimeProbe.shared.markPendingCopyDismissed()
            }
            guard case .clipboardPending = dictationState else {
                hidePanel()
                return
            }

            hidePanel()
            workflowController.dictationViewModel.send(.resetTapped)
        }

        func togglePanel() {
            guard !requiresOnboarding || onboardingStepState.allowsAudioCapture || isPanelVisible else {
                presentRequiredPermissionsGateIfNeeded()
                return
            }

            guard hasRequiredPermissions || isPanelVisible else {
                presentRequiredPermissionsGateIfNeeded()
                return
            }

            guard let presentationModel else { return }
            shellPresentationController.togglePanel(appModel: presentationModel)
        }

        func previewPermissionIndicators() {
            refreshPermissionIndicators()
        }

        func chooseOnboardingMode(_ mode: MacOnboardingMode) {
            guard requiresOnboarding else {
                onboardingModeState = mode
                onboardingStepState = .done
                notifyChange()
                return
            }

            onboardingModeState = mode
            onboardingStepState = mode == .apiKey ? .apiKey : .login
            notifyChange()
        }

        func selectOnboardingAppearanceTheme(_ theme: MacDictationVisualTheme) {
            onboardingAppearanceThemeState = theme
            hasAppliedOnboardingAppearanceTheme = false
            notifyChange()
        }

        func applyOnboardingAppearanceTheme() {
            defaults.set(onboardingAppearanceThemeState.rawValue, forKey: MacPreferences.shaderTheme)
            hasAppliedOnboardingAppearanceTheme = true
            notifyChange()
        }

        func advanceOnboarding() {
            guard requiresOnboarding else {
                onboardingStepState = .done
                notifyChange()
                return
            }

            switch onboardingStepState {
            case .permissions:
                guard hasRequiredPermissions else { return }
                onboardingStepState = .shortcut
            case .shortcut:
                prepareFirstSuccessStep()
                onboardingStepState = .firstSuccess
            case .firstSuccess:
                guard canContinueFirstSuccessOnboarding || canSkipFirstSuccessOnboarding else { return }
                onboardingStepState = .appearance
            case .apiKey, .login, .appearance, .done:
                break
            }

            notifyChange()
        }

        func retreatOnboarding() {
            guard requiresOnboarding else {
                onboardingStepState = .done
                notifyChange()
                return
            }

            switch onboardingStepState {
            case .apiKey, .login:
                if onboardingStepState == .apiKey {
                    onboardingStepState = .login
                }
            case .permissions:
                if requiresOnboarding {
                    onboardingStepState = onboardingModeState == .managed ? .login : .apiKey
                }
            case .shortcut:
                onboardingStepState = .permissions
            case .firstSuccess:
                onboardingStepState = .shortcut
            case .appearance:
                onboardingStepState = .firstSuccess
            case .done:
                onboardingStepState = .appearance
            }

            notifyChange()
        }

        func completeCredentialOnboarding(mode: MacOnboardingMode) {
            onboardingModeState = mode
            guard requiresOnboarding else {
                onboardingStepState = .done
                notifyChange()
                return
            }

            onboardingStepState = .permissions
            notifyChange()
        }

        func finishOnboarding() {
            defaults.set(true, forKey: MacPreferences.onboardingCompleted)
            onboardingStepState = .done
            onboardingModeState = nil
            permissionGateController.hide()
            notifyChange()
        }

        var canFinishAppearanceOnboarding: Bool {
            hasAppliedOnboardingAppearanceTheme
        }

        func setDebugForceOnboardingEnabled(_ enabled: Bool) {
            defaults.set(enabled, forKey: MacPreferences.debugForceOnboarding)

            #if DEBUG
                if !enabled {
                    defaults.set(true, forKey: MacPreferences.onboardingCompleted)
                }
            #endif

            resetOnboardingProgressIfNeeded()
            notifyChange()
        }

        func resetOnboardingForDebug() {
            defaults.set(false, forKey: MacPreferences.onboardingCompleted)
            onboardingModeState = nil
            resetOnboardingProgressIfNeeded(forceRestart: true)
            notifyChange()
        }

        func applyDockVisibility(showInDock: Bool) {
            shellPresentationController.applyDockVisibility(showInDock: showInDock)
        }

        func openSettings(using action: () -> Void) {
            shellPresentationController.openSettings(
                currentShowInDockPreference: currentShowInDockPreference,
                using: action
            )
        }

        func settingsDidAppear() {
            shellPresentationController.settingsDidAppear(
                currentShowInDockPreference: currentShowInDockPreference
            )
        }

        func settingsDidDisappear() {
            shellPresentationController.settingsDidDisappear(
                currentShowInDockPreference: currentShowInDockPreference
            )
        }

        func refreshRuntimeFromSettings() {
            applyDockVisibility(showInDock: currentShowInDockPreference)
            notifyChange()
        }

        private func notifyChange() {
            syncOnboardingPresentation()
            onChange?()
        }

        private var currentShowInDockPreference: Bool {
            defaults.object(forKey: MacPreferences.showInDock) as? Bool ?? false
        }

        private var requiresOnboarding: Bool {
            return isDebugForceOnboardingEnabled || !defaults.bool(forKey: MacPreferences.onboardingCompleted)
        }

        private var shouldPresentOnboardingGate: Bool {
            requiresOnboarding && !onboardingStepState.allowsAudioCapture
        }

        private var shouldPresentRuntimePermissionFailureWindow: Bool {
            !hasRequiredPermissions
        }

        private var shouldPresentPermissionGate: Bool {
            shouldPresentOnboardingGate || shouldPresentRuntimePermissionFailureWindow
        }

        private func performPrimaryAction(source: PrimaryActionSource) {
            Task {
                await DictationRuntimeProbe.shared.markAction("performPrimaryAction:\(source)")
            }

            if requiresOnboarding && !onboardingStepState.allowsAudioCapture {
                presentRequiredPermissionsGateIfNeeded()
                return
            }

            switch dictationState {
            case .idle, .result, .error:
                if source == .interface {
                    Task {
                        await DictationStartupProbe.shared.begin(trigger: .interface)
                    }
                }
                requestDictationCaptureStart(from: source)
            case .clipboardPending(let text):
                commitPendingCopy(text)
            case .starting:
                requestDictationCaptureStopIfNeeded()
            case .listening:
                requestDictationCaptureStopIfNeeded()
            case .processing:
                break
            }
        }

        private func handleHotkeyPressed() {
            let action = hotkeyInteraction.handleKeyDown(
                for: dictationState,
                now: ProcessInfo.processInfo.systemUptime
            )
            if action == .startCapture {
                Task {
                    await DictationStartupProbe.shared.begin(trigger: .hotkey)
                }
            }
            performHotkeyAction(action)
        }

        private func handleHotkeyReleased() {
            let action = hotkeyInteraction.handleKeyUp(
                for: dictationState,
                now: ProcessInfo.processInfo.systemUptime
            )
            performHotkeyAction(action)
        }

        private func showTransientPanel() {
            guard let presentationModel else { return }
            shellPresentationController.showTransientPanel(appModel: presentationModel)
            Task {
                await DictationRuntimeProbe.shared.markPanelShown()
            }
            Task {
                await DictationStartupProbe.shared.record(.panelShown)
            }
        }

        private func bindState() {
            workflowController.dictationViewModel.$state
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.handleDictationStateChange(state)
                }
                .store(in: &cancellables)
        }

        private func bindLifecycleNotifications() {
            notificationCenter.publisher(for: NSApplication.willResignActiveNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.handleAppLifecycleChange(to: "inactive")
                }
                .store(in: &cancellables)

            notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.refreshPermissionIndicators()
                    self?.handleAppLifecycleChange(to: "active")
                }
                .store(in: &cancellables)
        }

        private func refreshPermissionIndicators() {
            resetOnboardingProgressIfNeeded()

            if shouldPresentPermissionGate {
                if !requiresOnboarding {
                    onboardingStepState = .permissions
                }
            } else {
                permissionGateController.hide()
            }

            notifyChange()
        }

        private func handleDictationStateChange(_ state: DictationState) {
            handleStateTransitionObservation(for: state)
            handlePanelAndIdleLifecycle(for: state)
            handleResultLifecycle(for: state)
        }

        private func handleStateTransitionObservation(for state: DictationState) {
            let previousState = previousDictationState
            previousDictationState = state
            hotkeyInteraction.sync(with: state)
            Task {
                await DictationRuntimeProbe.shared.markStateTransition(from: previousState, to: state)
                if state == .idle, previousState != .idle {
                    await DictationRuntimeProbe.shared.endRun(
                        reason: "state_idle", details: "from=\(stateLabel(previousState))")
                }
            }
            cancelPendingStateTasks()
            updateOnboardingProgress(previousState: previousState, state: state)
            workflowController.handleStateTransition(from: previousState, to: state)
        }

        private func handlePanelAndIdleLifecycle(for state: DictationState) {
            switch state {
            case .starting, .listening, .error, .clipboardPending:
                showTransientPanelIfNeeded()
            case .idle:
                guard workflowController.activeRecordingSource == nil else { return }
                workflowController.resetWorkflowIfNeeded()
                scheduleTransientPanelHideIfNeeded()
            case .processing, .result:
                break
            }
        }

        private func handleResultLifecycle(for state: DictationState) {
            guard case .result(let text) = state else { return }

            completionHandlingTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let outcome = await workflowController.handleCompletedResult(
                    text: text,
                    showTransientPanel: showTransientPanel
                )
                let recoveredTextPreserved =
                    if case .failed(let failure) = outcome {
                        failure.preservesRecoveredTextInClipboard
                    } else {
                        false
                    }
                Task {
                    await DictationRuntimeProbe.shared.markResultHandled(
                        clipboardPending: outcome == .clipboardPending || recoveredTextPreserved,
                        textLength: text.count
                    )
                }

                guard !Task.isCancelled else {
                    AppLogger.info(
                        "OutputTrace stage=session_result_mapping_skipped reason=task_cancelled outcome=\(completionOutcomeLabel(outcome))",
                        category: .perfTrace
                    )
                    return
                }
                guard case .result = dictationState else {
                    AppLogger.info(
                        "OutputTrace stage=session_result_mapping_skipped reason=state_changed currentState=\(stateLabel(dictationState)) outcome=\(completionOutcomeLabel(outcome))",
                        category: .perfTrace
                    )
                    return
                }

                AppLogger.info(
                    "OutputTrace stage=session_result_mapping_apply outcome=\(completionOutcomeLabel(outcome)) recoveredTextPreserved=\(recoveredTextPreserved) panelVisible=\(isPanelVisible)",
                    category: .perfTrace
                )

                switch outcome {
                case .completed:
                    hidePanel()
                    workflowController.dictationViewModel.send(.resetTapped)
                case .clipboardPending:
                    if !isPanelVisible {
                        showTransientPanel()
                    }
                    workflowController.dictationViewModel.send(.clipboardPending(text))
                case .failed(let failure):
                    if failure.preservesRecoveredTextInClipboard {
                        if !isPanelVisible {
                            showTransientPanel()
                        }
                        workflowController.dictationViewModel.send(.clipboardPending(text))
                    } else {
                        workflowController.dictationViewModel.send(.transcriptionFailed(failure))
                    }
                }
            }
        }

        private func cancelPendingStateTasks() {
            completionHandlingTask?.cancel()
            completionHandlingTask = nil
            shellPresentationController.cancelScheduledPanelHide()
        }

        private func scheduleTransientPanelHideIfNeeded() {
            shellPresentationController.scheduleTransientPanelHideIfNeeded { [weak self] in
                self?.dictationState ?? .idle
            }
        }

        private func showTransientPanelIfNeeded() {
            guard !isPanelVisible else { return }
            showTransientPanel()
        }

        private func registerHotkeys() {
            hotkeyRegistrar.clearDictationHandlers()
            hotkeyRegistrar.registerDictationKeyDown { [weak self] in
                self?.handleHotkeyPressed()
            }
            hotkeyRegistrar.registerDictationKeyUp { [weak self] in
                self?.handleHotkeyReleased()
            }
        }

        private func performHotkeyAction(_ action: MacDictationHotkeyInteraction.Action) {
            switch action {
            case .none:
                break
            case .startCapture:
                requestDictationCaptureStart(from: .hotkey)
            case .stopCapture:
                requestDictationCaptureStopIfNeeded()
            }
        }

        private func requestDictationCaptureStart(from source: PrimaryActionSource) {
            if requiresOnboarding && !onboardingStepState.allowsAudioCapture {
                Task {
                    await DictationStartupProbe.shared.record(.failed, note: "onboarding_gate")
                }
                presentRequiredPermissionsGateIfNeeded()
                return
            }

            guard hasRequiredPermissions else {
                Task {
                    await DictationStartupProbe.shared.record(.failed, note: "permissions_gate")
                }

                presentRequiredPermissionsGateIfNeeded()
                return
            }

            Task {
                await DictationStartupProbe.shared.record(.permissionsVerified)
                await DictationRuntimeProbe.shared.endRun(reason: "start_requested_after_previous")
                await DictationRuntimeProbe.shared.markCaptureStartRequested()
                await DictationRuntimeProbe.shared.beginRun(
                    trigger: "captureStart",
                    source: "MacAppSessionController",
                    panelVisible: isPanelVisible
                )
            }

            switch dictationState {
            case .idle:
                startDictationCapture(from: source)
            case .result, .error:
                workflowController.dictationViewModel.send(.resetTapped)
                startDictationCapture(from: source)
            case .clipboardPending, .starting, .listening, .processing:
                break
            }
        }

        private func startDictationCapture(from source: PrimaryActionSource) {
            workflowController.startDictationCapture(
                source: source,
                allowCurrentAppTarget: requiresOnboarding && onboardingStepState == .firstSuccess,
                showTransientPanel: { [weak self] in
                    self?.showTransientPanel()
                }
            )
            Task {
                await DictationRuntimeProbe.shared.markAction("startDictationCapture")
            }
        }

        private func requestDictationCaptureStopIfNeeded() {
            Task {
                await DictationRuntimeProbe.shared.markCaptureStopRequested()
            }
            guard dictationState.isCaptureInFlight else { return }
            workflowController.stopActiveCapture()
        }

        private func commitPendingCopy(_ text: String) {
            let copied = workflowController.copyPendingResultToClipboard(text)
            guard copied else {
                return
            }

            hidePanel()
            workflowController.dictationViewModel.send(.resetTapped)
            Task {
                await DictationRuntimeProbe.shared.markPendingCopyCommitted()
            }
        }

        private func presentRequiredPermissionsGateIfNeeded() {
            if shouldPresentOnboardingGate {
                syncOnboardingPresentation()
                return
            }

            guard shouldPresentPermissionGate else {
                permissionGateController.hide()
                return
            }

            // If a capture or processing is already in flight, do not interrupt the UI
            // by hiding the panel and showing the permissions gate. This avoids a
            // race condition where the app launch permission refresh hides a panel
            // the user just opened.
            guard dictationState == .idle else {
                return
            }

            if isPanelVisible {
                shellPresentationController.hidePanel()
            }

            guard let presentationModel else { return }
            permissionGateController.show(appModel: presentationModel)
        }

        private func updateOnboardingProgress(previousState: DictationState, state: DictationState) {
            if onboardingStepState == .firstSuccess {
                if case .result(let text) = state {
                    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    firstSuccessPreviewTextState = trimmedText.isEmpty ? nil : trimmedText
                    firstSuccessFailureMessageState = nil
                } else if case .clipboardPending(let text) = state {
                    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    firstSuccessPreviewTextState = trimmedText.isEmpty ? nil : trimmedText
                    firstSuccessFailureMessageState = nil
                } else if case .error(let failure) = state {
                    firstSuccessFailureCount += 1
                    firstSuccessFailureMessageState = inferredFirstSuccessFailureMessage(for: failure)
                }
            }

            notifyChange()
        }

        private func resetShortcutOnboardingState() {
            shortcutTestDetectedPressState = false
            shortcutTestCompletedRoundTripState = false
            shortcutTestPreviewTextState = nil
        }

        private func prepareFirstSuccessStep() {
            firstSuccessPreviewTextState = nil
            firstSuccessFailureMessageState = nil
            firstSuccessFailureCount = 0

            switch dictationState {
            case .result, .error, .clipboardPending:
                workflowController.dictationViewModel.send(.resetTapped)
            case .idle, .starting, .listening, .processing:
                break
            }
        }

        private func matchesListening(_ state: DictationState) -> Bool {
            state.isCaptureInFlight
        }

        private func inferredFirstSuccessFailureMessage(for failure: DictationFailure) -> String {
            if failure == .autoPastePermissionMissing {
                return "Unable to paste automatically, please grant Input Monitoring or Accessibility access."
            }

            switch failure.classification {
            case .authentication:
                return "Connection unavailable, please re-verify your login status."
            case .configuration:
                if onboardingModeState == .apiKey {
                    return "Connection unavailable, please re-verify your API Key."
                }
                return "Model configuration unavailable, please check provider settings."
            case .network:
                return "Processing failed, please check your network or model configuration."
            case .permissions:
                return "Unable to access microphone, please check system permissions."
            case .noSpeech:
                return "No voice input detected, please try again."
            case .output:
                return "Text output failed, but your transcription is available."
            case .service, .state, .unknown:
                return "Dictation failed, please try again."
            }
        }

        private func requestMicrophoneAccess() {
            Task { @MainActor [weak self] in
                guard let self else { return }

                AppLogger.info("Requesting microphone access from permissions gate", category: .permissions)
                _ = await permissionManager.requestMicrophonePermission()
                refreshPermissionIndicators()
            }
        }

        private func handleAppLifecycleChange(to newState: String) {
            let from = appLifecycleState
            guard from != newState else { return }
            appLifecycleState = newState

            Task {
                await DictationRuntimeProbe.shared.markAppStateChange(from: from, to: newState)
            }
        }

        private func stateLabel(_ state: DictationState) -> String {
            switch state {
            case .idle:
                return "idle"
            case .starting:
                return "starting"
            case .listening:
                return "listening"
            case .processing:
                return "processing"
            case .result:
                return "result"
            case .clipboardPending:
                return "clipboardPending"
            case .error:
                return "error"
            }
        }

        private func completionOutcomeLabel(
            _ outcome: MacDictationCaptureCoordinator.CompletionOutcome
        ) -> String {
            switch outcome {
            case .completed:
                return "completed"
            case .clipboardPending:
                return "clipboardPending"
            case .failed(let failure):
                return "failed:\(failureLabel(failure))"
            }
        }

        private func failureLabel(_ failure: DictationFailure) -> String {
            switch failure {
            case .clipboardWriteFailed:
                return "clipboardWriteFailed"
            case .autoPastePermissionMissing:
                return "autoPastePermissionMissing"
            case .pasteVerificationUnavailable:
                return "pasteVerificationUnavailable"
            case .pasteVerificationFailed:
                return "pasteVerificationFailed"
            default:
                return "other"
            }
        }

        private var isDebugForceOnboardingEnabled: Bool {
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

        private func resetOnboardingProgressIfNeeded(forceRestart: Bool = false) {
            guard requiresOnboarding else {
                onboardingStepState = .done
                if !isDebugForceOnboardingEnabled {
                    onboardingModeState = nil
                }
                return
            }

            guard forceRestart || onboardingStepState == .done else {
                return
            }

            onboardingStepState = .login
        }

        private func syncOnboardingPresentation() {
            guard let presentationModel else {
                return
            }

            if requiresOnboarding, onboardingStepState != .done {
                onboardingWindowController.show(appModel: presentationModel)
            } else {
                onboardingWindowController.hide()
            }
        }

    }
#endif
