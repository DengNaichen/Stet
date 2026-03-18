#if os(macOS)
import AppKit
import Combine
import Foundation

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
    private var stateResetTask: Task<Void, Never>?
    private var hotkeyInteraction = MacDictationHotkeyInteraction()
    private var previousDictationState: DictationState = .idle
    private weak var presentationModel: (any MacAppPresentationModeling)?

    init(
        workflowController: MacDictationWorkflowController,
        shellPresentationController: (any MacShellPresenting)? = nil,
        permissionGateController: (any MacPermissionGatePresenting)? = nil,
        permissionManager: MacPermissionManager,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        hotkeyRegistrar: (any MacDictationHotkeyRegistering)? = nil
    ) {
        self.workflowController = workflowController
        self.shellPresentationController = shellPresentationController ?? MacShellPresentationController()
        self.permissionGateController = permissionGateController ?? MacPermissionGateController()
        self.permissionManager = permissionManager
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.hotkeyRegistrar = hotkeyRegistrar ?? KeyboardShortcutsHotkeyRegistrar()

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

    func togglePanel() {
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

    private func performPrimaryAction(source: PrimaryActionSource) {
        switch dictationState {
        case .idle, .result, .error:
            requestDictationCaptureStart(from: source)
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
        if hasRequiredPermissions {
            permissionGateController.hide()
        } else {
            presentRequiredPermissionsGateIfNeeded()
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
        workflowController.handleStateTransition(from: previousState, to: state)
    }

    private func handlePanelAndIdleLifecycle(for state: DictationState) {
        switch state {
        case .listening, .error:
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            await workflowController.handleCompletedResult(
                text: text,
                workflow: completedWorkflow,
                showTransientPanel: showTransientPanel
            )
        }

        scheduleStateReset()
    }

    private func cancelPendingStateTasks() {
        stateResetTask?.cancel()
        stateResetTask = nil
        shellPresentationController.cancelScheduledPanelHide()
    }

    private func scheduleStateReset() {
        stateResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self else { return }
            guard case .result = dictationState else { return }
            workflowController.dictationViewModel.send(.resetTapped)
        }
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
        case .listening, .processing:
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

    private func presentRequiredPermissionsGateIfNeeded() {
        guard !hasRequiredPermissions else {
            permissionGateController.hide()
            return
        }

        if isPanelVisible {
            shellPresentationController.hidePanel()
        }

        guard let presentationModel else { return }
        permissionGateController.show(appModel: presentationModel)
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
