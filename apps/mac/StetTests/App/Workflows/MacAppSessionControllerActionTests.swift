#if os(macOS)
import Foundation
import Testing

@testable import Stet

@MainActor
private final class FakeShellPresenter: MacShellPresenting {
    var onVisibilityChange: (() -> Void)?

    private(set) var isPanelVisible = false

    private(set) var showPanelCallCount = 0
    private(set) var showTransientPanelCallCount = 0
    private(set) var hidePanelCallCount = 0
    private(set) var togglePanelCallCount = 0
    private(set) var panelDidHideCallCount = 0
    private(set) var cancelScheduledPanelHideCallCount = 0
    private(set) var scheduleTransientPanelHideCallCount = 0
    private(set) var applyDockVisibilityCallCount = 0
    private(set) var lastShowInDockValue: Bool?

    func showPanel(appModel: any MacDictationPanelCoordinating) {
        showPanelCallCount += 1
        isPanelVisible = true
        onVisibilityChange?()
    }

    func showTransientPanel(appModel: any MacDictationPanelCoordinating) {
        showTransientPanelCallCount += 1
        isPanelVisible = true
        onVisibilityChange?()
    }

    func hidePanel() {
        hidePanelCallCount += 1
        isPanelVisible = false
        onVisibilityChange?()
    }

    func togglePanel(appModel: any MacDictationPanelCoordinating) {
        togglePanelCallCount += 1
        isPanelVisible.toggle()
        onVisibilityChange?()
    }

    func panelDidHide() {
        panelDidHideCallCount += 1
        isPanelVisible = false
    }

    func cancelScheduledPanelHide() {
        cancelScheduledPanelHideCallCount += 1
    }

    func scheduleTransientPanelHideIfNeeded(currentState: @escaping @MainActor () -> DictationState) {
        scheduleTransientPanelHideCallCount += 1
        _ = currentState()
    }

    func applyDockVisibility(showInDock: Bool) {
        applyDockVisibilityCallCount += 1
        lastShowInDockValue = showInDock
    }

    func openSettings(currentShowInDockPreference: Bool, using action: () -> Void) {
        action()
    }

    func settingsDidAppear(currentShowInDockPreference: Bool) {}

    func settingsDidDisappear(currentShowInDockPreference: Bool) {}
}

@MainActor
private final class FakePermissionGatePresenter: MacPermissionGatePresenting {
    private(set) var showCallCount = 0
    private(set) var hideCallCount = 0

    func show(appModel: any MacPermissionsCoordinating) {
        showCallCount += 1
    }

    func hide() {
        hideCallCount += 1
    }
}

@MainActor
private final class FakeHotkeyRegistrar: MacDictationHotkeyRegistering {
    private(set) var clearDictationHandlersCallCount = 0
    private(set) var registerKeyDownCallCount = 0
    private(set) var registerKeyUpCallCount = 0

    func clearDictationHandlers() {
        clearDictationHandlersCallCount += 1
    }

    func registerDictationKeyDown(_ handler: @escaping () -> Void) {
        registerKeyDownCallCount += 1
    }

    func registerDictationKeyUp(_ handler: @escaping () -> Void) {
        registerKeyUpCallCount += 1
    }
}

@MainActor
private final class FakeMediaPlaybackController: MediaPlaybackControlling {
    private(set) var pausePlaybackIfNeededCallCount = 0
    private(set) var resumePlaybackIfNeededCallCount = 0

    func pausePlaybackIfNeeded() {
        pausePlaybackIfNeededCallCount += 1
    }

    func resumePlaybackIfNeeded() {
        resumePlaybackIfNeededCallCount += 1
    }
}

@MainActor
@Suite("Mac App Session Controller Action Behavior", .serialized)
struct MacAppSessionControllerActionTests {
    private func makeSubject() -> (
        session: MacAppSessionController,
        workflow: MacDictationWorkflowController,
        shell: FakeShellPresenter,
        permissionGate: FakePermissionGatePresenter
    ) {
        let defaults = TestSupport.makeUserDefaults()
        let speechService = ControllableSpeechService()
        let textInjectionService = TestTextInjectionService()
        let clipboardService = TestClipboardService()
        let mediaPlaybackController = FakeMediaPlaybackController()
        let settingsStore = DictationSettingsStore(
            defaults: defaults,
            secretStore: TestSecretStore()
        )
        let dictationViewModel = DictationViewModel(speechService: speechService)
        let captureCoordinator = MacDictationCaptureCoordinator(
            clipboardService: clipboardService,
            textInjectionService: textInjectionService
        )
        let workflow = MacDictationWorkflowController(
            dictationViewModel: dictationViewModel,
            captureCoordinator: captureCoordinator,
            textInjectionService: textInjectionService,
            mediaPlaybackController: mediaPlaybackController,
            settingsStore: settingsStore,
            interactionSoundPlayer: InteractionSoundPlayer()
        )
        let permissionManager = MacPermissionManager(textInjectionService: textInjectionService)
        let shell = FakeShellPresenter()
        let permissionGate = FakePermissionGatePresenter()
        let hotkeyRegistrar = FakeHotkeyRegistrar()

        let session = MacAppSessionController(
            workflowController: workflow,
            shellPresentationController: shell,
            permissionGateController: permissionGate,
            permissionManager: permissionManager,
            hotkeyRegistrar: hotkeyRegistrar
        )

        return (session: session, workflow: workflow, shell: shell, permissionGate: permissionGate)
    }

    @Test func cancelActiveCaptureHidesPanelAndResetsWorkflowState() {
        let subject = makeSubject()

        subject.workflow.startDictationCapture(source: .interface) {}

        #expect(subject.workflow.dictationViewModel.state == .listening)
        #expect(subject.workflow.activeRecordingSource == .interface)
        #expect(subject.shell.hidePanelCallCount == 0)

        subject.session.cancelActiveCapture()

        #expect(subject.workflow.activeRecordingSource == nil)
        #expect(subject.workflow.dictationViewModel.state == .idle)
        #expect(subject.shell.hidePanelCallCount == 1)
        #expect(subject.shell.isPanelVisible == false)
    }

    @Test func dismissPendingCopyHidesPanelAndResetsClipboardPendingState() async {
        let subject = makeSubject()

        subject.workflow.dictationViewModel.send(.clipboardPending("needs copy"))

        #expect(await TestSupport.eventually { subject.workflow.dictationViewModel.state == .clipboardPending("needs copy") })
        #expect(subject.shell.hidePanelCallCount == 0)

        subject.session.dismissPendingCopy()

        #expect(await TestSupport.eventually { subject.workflow.dictationViewModel.state == .idle })
        #expect(subject.shell.hidePanelCallCount == 1)
        #expect(subject.shell.isPanelVisible == false)
    }
}

#endif
