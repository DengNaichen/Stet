#if os(macOS)
import AppKit
import Combine
import Foundation
internal import Auth

@MainActor
final class MacAppSessionController {
    typealias PrimaryActionSource = MacDictationWorkflowController.PrimaryActionSource

    var onChange: (() -> Void)?

    private let workflowController: MacDictationWorkflowController
    private let shellPresentationController: any MacShellPresenting
    private let permissionGateController: any MacPermissionGatePresenting
    private let permissionManager: MacPermissionManager
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
    private var shortcutTestDetectedPressState = false
    private var shortcutTestCompletedRoundTripState = false
    private var shortcutTestPreviewTextState: String?
    private var firstSuccessPreviewTextState: String?
    private var firstSuccessFailureMessageState: String?
    private var firstSuccessFailureCount = 0

    init(
        workflowController: MacDictationWorkflowController,
        shellPresentationController: any MacShellPresenting,
        permissionGateController: any MacPermissionGatePresenting,
        permissionManager: MacPermissionManager,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        hotkeyRegistrar: any MacDictationHotkeyRegistering
    ) {
        self.workflowController = workflowController
        self.shellPresentationController = shellPresentationController
        self.permissionGateController = permissionGateController
        self.permissionManager = permissionManager
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.hotkeyRegistrar = hotkeyRegistrar
        self.onboardingStepState = defaults.bool(forKey: MacPreferences.onboardingCompleted) ? .done : .welcome

        configure()
    }

    // Convenience: default dependencies
    convenience init(
        workflowController: MacDictationWorkflowController,
        permissionManager: MacPermissionManager,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.init(
            workflowController: workflowController,
            shellPresentationController: MacShellPresentationController(),
            permissionGateController: MacPermissionGateController(),
            permissionManager: permissionManager,
            defaults: defaults,
            notificationCenter: notificationCenter,
            hotkeyRegistrar: KeyboardShortcutsHotkeyRegistrar()
        )
    }

    // Backwards-compatible convenience initializer (deprecated)
    @available(*, deprecated, message: "Use the designated initializer with non-optional dependencies or the convenience initializer without dependencies.")
    convenience init(
        workflowController: MacDictationWorkflowController,
        shellPresentationController: (any MacShellPresenting)? = nil,
        permissionGateController: (any MacPermissionGatePresenting)? = nil,
        permissionManager: MacPermissionManager,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        hotkeyRegistrar: (any MacDictationHotkeyRegistering)? = nil
    ) {
        self.init(
            workflowController: workflowController,
            shellPresentationController: shellPresentationController ?? MacShellPresentationController(),
            permissionGateController: permissionGateController ?? MacPermissionGateController(),
            permissionManager: permissionManager,
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
        onboardingStepState
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
            self?.refreshPermissionIndicators()
        }
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
        shellPresentationController.hidePanel()
    }

    func dismissPendingCopy() {
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
        onboardingModeState = mode
        onboardingStepState = mode == .apiKey ? .apiKey : .login
        notifyChange()
    }

    func advanceOnboarding() {
        switch onboardingStepState {
        case .welcome:
            onboardingStepState = .mode
        case .permissions:
            guard hasRequiredPermissions else { return }
            resetShortcutOnboardingState()
            onboardingStepState = .shortcut
        case .shortcut:
            guard canContinueShortcutOnboarding else { return }
            prepareFirstSuccessStep()
            onboardingStepState = .firstSuccess
        case .firstSuccess:
            guard canContinueFirstSuccessOnboarding || canSkipFirstSuccessOnboarding else { return }
            onboardingStepState = .done
        case .mode, .apiKey, .login, .done:
            break
        }

        notifyChange()
    }

    func retreatOnboarding() {
        switch onboardingStepState {
        case .mode:
            onboardingStepState = .welcome
        case .apiKey, .login:
            onboardingStepState = .mode
        case .permissions:
            if requiresOnboarding {
                onboardingStepState = onboardingModeState == .managed ? .login : .apiKey
            }
        case .shortcut:
            onboardingStepState = .permissions
        case .firstSuccess:
            onboardingStepState = .shortcut
        case .done:
            onboardingStepState = .firstSuccess
        case .welcome:
            break
        }

        notifyChange()
    }

    func completeCredentialOnboarding(mode: MacOnboardingMode) {
        onboardingModeState = mode
        onboardingStepState = .permissions
        notifyChange()
    }

    func finishOnboarding() {
        defaults.set(true, forKey: MacPreferences.onboardingCompleted)
        onboardingStepState = .done
        permissionGateController.hide()
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
        onChange?()
    }

    private var currentShowInDockPreference: Bool {
        defaults.object(forKey: MacPreferences.showInDock) as? Bool ?? false
    }

    private var requiresOnboarding: Bool {
        !(defaults.object(forKey: MacPreferences.onboardingCompleted) as? Bool ?? false)
    }

    private var shouldPresentOnboardingGate: Bool {
        requiresOnboarding || !hasRequiredPermissions
    }

    private func performPrimaryAction(source: PrimaryActionSource) {
        if requiresOnboarding && !onboardingStepState.allowsAudioCapture {
            presentRequiredPermissionsGateIfNeeded()
            return
        }

        switch dictationState {
        case .idle, .result, .error:
            requestDictationCaptureStart(from: source)
        case .clipboardPending(let text):
            commitPendingCopy(text)
        case .listening:
            requestDictationCaptureStopIfListening()
        case .processing:
            break
        }
    }

    private func handleHotkeyPressed() {
        let action = hotkeyInteraction.handleKeyDown(
            for: dictationState,
            now: ProcessInfo.processInfo.systemUptime
        )
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
    }

    private func bindState() {
        workflowController.dictationViewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleDictationStateChange(state)
            }
            .store(in: &cancellables)
    }

    private func bindLifecycleNotifications() {
        notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPermissionIndicators()
            }
            .store(in: &cancellables)
    }

    private func refreshPermissionIndicators() {
        if shouldPresentOnboardingGate {
            if !requiresOnboarding {
                onboardingStepState = .permissions
            }
            presentRequiredPermissionsGateIfNeeded()
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
        cancelPendingStateTasks()
        updateOnboardingProgress(previousState: previousState, state: state)
        workflowController.handleStateTransition(from: previousState, to: state)
    }

    private func handlePanelAndIdleLifecycle(for state: DictationState) {
        switch state {
        case .listening, .error:
            showTransientPanel()
        case .clipboardPending:
            showTransientPanel()
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

        let completedWorkflow = workflowController.activeWorkflow
        completionHandlingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await workflowController.handleCompletedResult(
                text: text,
                workflow: completedWorkflow,
                showTransientPanel: showTransientPanel
            )

            guard !Task.isCancelled else { return }
            guard case .result = dictationState else { return }

            switch outcome {
            case .completed:
                hidePanel()
                workflowController.dictationViewModel.send(.resetTapped)
            case .clipboardPending:
                if !isPanelVisible {
                    showTransientPanel()
                }
                workflowController.dictationViewModel.send(.clipboardPending(text))
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
            requestDictationCaptureStopIfListening()
        }
    }

    private func requestDictationCaptureStart(from source: PrimaryActionSource) {
        if requiresOnboarding && !onboardingStepState.allowsAudioCapture {
            presentRequiredPermissionsGateIfNeeded()
            return
        }

        guard hasRequiredPermissions else {
            presentRequiredPermissionsGateIfNeeded()
            return
        }

        switch dictationState {
        case .idle:
            startDictationCapture(from: source)
        case .result, .error:
            workflowController.dictationViewModel.send(.resetTapped)
            startDictationCapture(from: source)
        case .clipboardPending, .listening, .processing:
            break
        }
    }

    private func startDictationCapture(from source: PrimaryActionSource) {
        workflowController.startDictationCapture(
            source: source,
            showTransientPanel: showTransientPanel
        )
    }

    private func requestDictationCaptureStopIfListening() {
        guard case .listening = dictationState else { return }
        workflowController.stopActiveCapture()
    }

    private func commitPendingCopy(_ text: String) {
        workflowController.copyPendingResultToClipboard(text)
        hidePanel()
        workflowController.dictationViewModel.send(.resetTapped)
    }

    private func presentRequiredPermissionsGateIfNeeded() {
        guard shouldPresentOnboardingGate else {
            permissionGateController.hide()
            return
        }

        if isPanelVisible {
            shellPresentationController.hidePanel()
        }

        guard let presentationModel else { return }
        permissionGateController.show(appModel: presentationModel)
    }

    private func updateOnboardingProgress(previousState: DictationState, state: DictationState) {
        if onboardingStepState == .shortcut {
            if case .listening = state {
                shortcutTestDetectedPressState = true
            }

            if case .listening = previousState, !matchesListening(state) {
                shortcutTestCompletedRoundTripState = true
            }

            if case .result(let text) = state {
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                shortcutTestPreviewTextState = trimmedText.isEmpty ? nil : trimmedText
            }
        }

        if onboardingStepState == .firstSuccess {
            if case .result(let text) = state {
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                firstSuccessPreviewTextState = trimmedText.isEmpty ? nil : trimmedText
                firstSuccessFailureMessageState = nil
            } else if case .error = state {
                firstSuccessFailureCount += 1
                firstSuccessFailureMessageState = inferredFirstSuccessFailureMessage()
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
        case .idle, .listening, .processing:
            break
        }
    }

    private func matchesListening(_ state: DictationState) -> Bool {
        if case .listening = state {
            return true
        }

        return false
    }

    private func inferredFirstSuccessFailureMessage() -> String {
        if onboardingModeState == .managed, SupabaseService.shared.currentSession == nil {
            return "当前连接不可用，请重新验证你的登录状态。"
        }

        if onboardingModeState == .apiKey,
           workflowController.statusText.localizedCaseInsensitiveContains("key") {
            return "当前连接不可用，请重新验证你的 API Key。"
        }

        if workflowController.statusText.localizedCaseInsensitiveContains("network")
            || workflowController.statusText.localizedCaseInsensitiveContains("api")
            || workflowController.statusText.localizedCaseInsensitiveContains("relay") {
            return "处理失败，请检查网络或模型配置。"
        }

        return "没有检测到语音输入，请再试一次。"
    }

    private func requestMicrophoneAccess() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            AppLogger.info("Requesting microphone access from permissions gate", category: .permissions)
            _ = await permissionManager.requestMicrophonePermission()
            refreshPermissionIndicators()
        }
    }
}
#endif
