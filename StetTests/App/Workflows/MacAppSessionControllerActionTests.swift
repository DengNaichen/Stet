#if os(macOS)
    import Combine
    import Foundation
    import StetVisuals
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
    private final class FakePresentationModel: MacAppPresentationModeling {
        private let updatesSubject = PassthroughSubject<Void, Never>()

        var updates: AnyPublisher<Void, Never> {
            updatesSubject.eraseToAnyPublisher()
        }

        var dictationState: DictationState = .idle
        var statusText: String = "Ready"
        var recordingLevel: Double = 0
        var audioFeatures: MacDictationCapsuleVisualSignals = .zero
        var detectedTargetApplication: AppInfo?
        var autoPasteStatusText: String = "Enabled"
        var microphoneAccessStatusText: String = "Allowed"
        var microphoneAccessNeedsAttention = false
        var microphonePermissionActionTitle: String = "Request Access"
        var autoPasteAccessNeedsAttention = false

        func hidePanel() {}
        func dismissPendingCopy() {}
        func cancelActiveCapture() {}
        func performPrimaryAction() {}
        func upgrade() {}
        func requestAutoPasteAccess() {}
        func resolveMicrophoneAccess() {}
        func openAccessibilitySettings() {}
    }

    private final class TestAppBranchWorkspace: AppBranchWorkspaceObserving {
        var frontmostApplication: AppBranchWorkspaceApplicationSnapshot?

        func observeFrontmostApplicationChanges(_ handler: @escaping () -> Void) -> AppBranchWorkspaceObservationToken {
            AppBranchWorkspaceObservationToken(observer: NSObject())
        }

        func removeObservation(_ token: AppBranchWorkspaceObservationToken) {}
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
            permissionGate: FakePermissionGatePresenter,
            clipboardService: TestClipboardService,
            textInjectionService: TestTextInjectionService
        ) {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.onboardingCompleted)
            defaults.set(false, forKey: MacPreferences.interactionSoundsEnabled)
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
                textInjectionService: textInjectionService,
                frontmostBundleIdentifierProvider: { nil }
            )
            let workflow = MacDictationWorkflowController(
                dictationViewModel: dictationViewModel,
                captureCoordinator: captureCoordinator,
                mediaPlaybackController: mediaPlaybackController,
                settingsStore: settingsStore,
                interactionSoundPlayer: InteractionSoundPlayer(),
                mediaResumeDelay: .zero
            )
            let permissionManager = MacPermissionManager(textInjectionService: textInjectionService)
            let shell = FakeShellPresenter()
            let permissionGate = FakePermissionGatePresenter()
            let hotkeyRegistrar = FakeHotkeyRegistrar()
            let appBranchMonitor = AppBranchMonitor(
                workspace: TestAppBranchWorkspace(),
                callbackQueue: DispatchQueue(label: "com.stet.tests.sessioncontroller.action.appbranch")
            )

            let session = MacAppSessionController(
                workflowController: workflow,
                shellPresentationController: shell,
                permissionGateController: permissionGate,
                permissionManager: permissionManager,
                appBranchMonitor: appBranchMonitor,
                hotkeyRegistrar: hotkeyRegistrar
            )

            return (
                session: session,
                workflow: workflow,
                shell: shell,
                permissionGate: permissionGate,
                clipboardService: clipboardService,
                textInjectionService: textInjectionService
            )
        }

        @Test func cancelActiveCaptureHidesPanelAndResetsWorkflowState() {
            let subject = makeSubject()

            subject.workflow.startDictationCapture(source: .interface) {}

            #expect(subject.workflow.dictationViewModel.state.isCaptureInFlight)
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

            #expect(
                await TestSupport.eventually {
                    subject.workflow.dictationViewModel.state == .clipboardPending("needs copy")
                })
            #expect(subject.shell.hidePanelCallCount == 0)

            subject.session.dismissPendingCopy()

            #expect(await TestSupport.eventually { subject.workflow.dictationViewModel.state == .idle })
            #expect(subject.shell.hidePanelCallCount == 1)
            #expect(subject.shell.isPanelVisible == false)
        }

        @Test func startCaptureShowsTransientPanelOnlyOnceAcrossStartingAndListening() async {
            let subject = makeSubject()
            let presentationModel = FakePresentationModel()
            subject.session.activate(presentationModel: presentationModel, showInDock: false)

            subject.workflow.startDictationCapture(source: .interface) {
                subject.shell.showTransientPanel(appModel: presentationModel)
            }

            #expect(
                await TestSupport.eventually {
                    subject.workflow.dictationViewModel.state == .listening
                })
            #expect(
                await TestSupport.eventually {
                    subject.shell.showTransientPanelCallCount == 1
                })
            #expect(subject.shell.isPanelVisible)
        }

        @Test func pendingCopyFailureKeepsPanelVisibleAndPreservesTranscript() async {
            let subject = makeSubject()
            let presentationModel = FakePresentationModel()
            subject.session.activate(presentationModel: presentationModel, showInDock: false)
            subject.workflow.dictationViewModel.send(.clipboardPending("needs copy"))
            subject.shell.showTransientPanel(appModel: presentationModel)
            subject.clipboardService.shouldFailCopy = true

            #expect(
                await TestSupport.eventually {
                    subject.workflow.dictationViewModel.state == .clipboardPending("needs copy")
                })
            #expect(subject.shell.isPanelVisible)

            subject.session.performPrimaryAction()

            #expect(
                await TestSupport.eventually {
                    subject.workflow.dictationViewModel.state == .clipboardPending("needs copy")
                })
            #expect(subject.shell.hidePanelCallCount == 0)
            #expect(subject.shell.isPanelVisible)
        }

        @Test func verificationFailureFallsBackToClipboardPendingSurface() async {
            let subject = makeSubject()
            let presentationModel = FakePresentationModel()
            subject.session.activate(presentationModel: presentationModel, showInDock: false)
            subject.textInjectionService.pasteOutcome = .verificationFailed

            subject.workflow.dictationViewModel.send(.transcriptionSucceeded("transcript"))

            #expect(
                await TestSupport.eventually {
                    subject.workflow.dictationViewModel.state == .clipboardPending("transcript")
                })
            #expect(subject.clipboardService.copiedTexts == ["transcript", "transcript"])
            #expect(subject.shell.isPanelVisible)
        }

        @Test func vsCodeVerificationUnavailableCompletesWithoutClipboardPendingSurface() async {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.onboardingCompleted)
            defaults.set(false, forKey: MacPreferences.interactionSoundsEnabled)
            let speechService = ControllableSpeechService()
            let textInjectionService = TestTextInjectionService()
            textInjectionService.pasteOutcome = .eventPostedVerificationUnavailableInTextInput
            let clipboardService = TestClipboardService()
            let mediaPlaybackController = FakeMediaPlaybackController()
            let settingsStore = DictationSettingsStore(
                defaults: defaults,
                secretStore: TestSecretStore()
            )
            let dictationViewModel = DictationViewModel(speechService: speechService)
            let captureCoordinator = MacDictationCaptureCoordinator(
                clipboardService: clipboardService,
                textInjectionService: textInjectionService,
                frontmostBundleIdentifierProvider: { "com.microsoft.VSCode" }
            )
            let workflow = MacDictationWorkflowController(
                dictationViewModel: dictationViewModel,
                captureCoordinator: captureCoordinator,
                mediaPlaybackController: mediaPlaybackController,
                settingsStore: settingsStore,
                interactionSoundPlayer: InteractionSoundPlayer(),
                mediaResumeDelay: .zero
            )
            let permissionManager = MacPermissionManager(textInjectionService: textInjectionService)
            let shell = FakeShellPresenter()
            let permissionGate = FakePermissionGatePresenter()
            let hotkeyRegistrar = FakeHotkeyRegistrar()
            let appBranchMonitor = AppBranchMonitor(
                workspace: TestAppBranchWorkspace(),
                callbackQueue: DispatchQueue(label: "com.stet.tests.sessioncontroller.action.appbranch")
            )

            let session = MacAppSessionController(
                workflowController: workflow,
                shellPresentationController: shell,
                permissionGateController: permissionGate,
                permissionManager: permissionManager,
                appBranchMonitor: appBranchMonitor,
                hotkeyRegistrar: hotkeyRegistrar
            )
            let presentationModel = FakePresentationModel()
            session.activate(presentationModel: presentationModel, showInDock: false)

            workflow.dictationViewModel.send(.transcriptionSucceeded("transcript"))

            #expect(
                await TestSupport.eventually {
                    workflow.dictationViewModel.state == .idle
                })
            #expect(clipboardService.copiedTexts == ["transcript"])
            #expect(textInjectionService.didRequestAccessIfNeeded == false)
            #expect(shell.isPanelVisible == false)
            #expect(shell.showTransientPanelCallCount == 0)
        }

        @Test func vsCodeVerificationFailureCompletesWithoutClipboardPendingSurface() async {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.onboardingCompleted)
            defaults.set(false, forKey: MacPreferences.interactionSoundsEnabled)
            let speechService = ControllableSpeechService()
            let textInjectionService = TestTextInjectionService()
            textInjectionService.pasteOutcome = .verificationFailed
            let clipboardService = TestClipboardService()
            let mediaPlaybackController = FakeMediaPlaybackController()
            let settingsStore = DictationSettingsStore(
                defaults: defaults,
                secretStore: TestSecretStore()
            )
            let dictationViewModel = DictationViewModel(speechService: speechService)
            let captureCoordinator = MacDictationCaptureCoordinator(
                clipboardService: clipboardService,
                textInjectionService: textInjectionService,
                frontmostBundleIdentifierProvider: { "com.microsoft.VSCode" }
            )
            let workflow = MacDictationWorkflowController(
                dictationViewModel: dictationViewModel,
                captureCoordinator: captureCoordinator,
                mediaPlaybackController: mediaPlaybackController,
                settingsStore: settingsStore,
                interactionSoundPlayer: InteractionSoundPlayer(),
                mediaResumeDelay: .zero
            )
            let permissionManager = MacPermissionManager(textInjectionService: textInjectionService)
            let shell = FakeShellPresenter()
            let permissionGate = FakePermissionGatePresenter()
            let hotkeyRegistrar = FakeHotkeyRegistrar()
            let appBranchMonitor = AppBranchMonitor(
                workspace: TestAppBranchWorkspace(),
                callbackQueue: DispatchQueue(
                    label: "com.stet.tests.sessioncontroller.action.appbranch.verificationfailed")
            )

            let session = MacAppSessionController(
                workflowController: workflow,
                shellPresentationController: shell,
                permissionGateController: permissionGate,
                permissionManager: permissionManager,
                appBranchMonitor: appBranchMonitor,
                hotkeyRegistrar: hotkeyRegistrar
            )
            let presentationModel = FakePresentationModel()
            session.activate(presentationModel: presentationModel, showInDock: false)

            workflow.dictationViewModel.send(.transcriptionSucceeded("transcript"))

            #expect(
                await TestSupport.eventually {
                    workflow.dictationViewModel.state == .idle
                })
            #expect(clipboardService.copiedTexts == ["transcript"])
            #expect(textInjectionService.didRequestAccessIfNeeded == false)
            #expect(shell.isPanelVisible == false)
            #expect(shell.showTransientPanelCallCount == 0)
        }

        @Test func vsCodeGenericVerificationUnavailableCompletesWithoutClipboardPendingSurface() async {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.onboardingCompleted)
            defaults.set(false, forKey: MacPreferences.interactionSoundsEnabled)
            let speechService = ControllableSpeechService()
            let textInjectionService = TestTextInjectionService()
            textInjectionService.pasteOutcome = .eventPostedVerificationUnavailable
            let clipboardService = TestClipboardService()
            let mediaPlaybackController = FakeMediaPlaybackController()
            let settingsStore = DictationSettingsStore(
                defaults: defaults,
                secretStore: TestSecretStore()
            )
            let dictationViewModel = DictationViewModel(speechService: speechService)
            let captureCoordinator = MacDictationCaptureCoordinator(
                clipboardService: clipboardService,
                textInjectionService: textInjectionService,
                frontmostBundleIdentifierProvider: { "com.microsoft.VSCode" }
            )
            let workflow = MacDictationWorkflowController(
                dictationViewModel: dictationViewModel,
                captureCoordinator: captureCoordinator,
                mediaPlaybackController: mediaPlaybackController,
                settingsStore: settingsStore,
                interactionSoundPlayer: InteractionSoundPlayer(),
                mediaResumeDelay: .zero
            )
            let permissionManager = MacPermissionManager(textInjectionService: textInjectionService)
            let shell = FakeShellPresenter()
            let permissionGate = FakePermissionGatePresenter()
            let hotkeyRegistrar = FakeHotkeyRegistrar()
            let appBranchMonitor = AppBranchMonitor(
                workspace: TestAppBranchWorkspace(),
                callbackQueue: DispatchQueue(
                    label: "com.stet.tests.sessioncontroller.action.appbranch.genericunavailable")
            )

            let session = MacAppSessionController(
                workflowController: workflow,
                shellPresentationController: shell,
                permissionGateController: permissionGate,
                permissionManager: permissionManager,
                appBranchMonitor: appBranchMonitor,
                hotkeyRegistrar: hotkeyRegistrar
            )
            let presentationModel = FakePresentationModel()
            session.activate(presentationModel: presentationModel, showInDock: false)

            workflow.dictationViewModel.send(.transcriptionSucceeded("transcript"))

            #expect(
                await TestSupport.eventually {
                    workflow.dictationViewModel.state == .idle
                })
            #expect(clipboardService.copiedTexts == ["transcript"])
            #expect(textInjectionService.didRequestAccessIfNeeded == false)
            #expect(shell.isPanelVisible == false)
            #expect(shell.showTransientPanelCallCount == 0)
        }

        @Test func nonProfiledGenericVerificationUnavailableStillShowsClipboardPendingSurface() async {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.onboardingCompleted)
            defaults.set(false, forKey: MacPreferences.interactionSoundsEnabled)
            let speechService = ControllableSpeechService()
            let textInjectionService = TestTextInjectionService()
            textInjectionService.pasteOutcome = .eventPostedVerificationUnavailable
            let clipboardService = TestClipboardService()
            let mediaPlaybackController = FakeMediaPlaybackController()
            let settingsStore = DictationSettingsStore(
                defaults: defaults,
                secretStore: TestSecretStore()
            )
            let dictationViewModel = DictationViewModel(speechService: speechService)
            let captureCoordinator = MacDictationCaptureCoordinator(
                clipboardService: clipboardService,
                textInjectionService: textInjectionService,
                frontmostBundleIdentifierProvider: { "com.apple.TextEdit" }
            )
            let workflow = MacDictationWorkflowController(
                dictationViewModel: dictationViewModel,
                captureCoordinator: captureCoordinator,
                mediaPlaybackController: mediaPlaybackController,
                settingsStore: settingsStore,
                interactionSoundPlayer: InteractionSoundPlayer(),
                mediaResumeDelay: .zero
            )
            let permissionManager = MacPermissionManager(textInjectionService: textInjectionService)
            let shell = FakeShellPresenter()
            let permissionGate = FakePermissionGatePresenter()
            let hotkeyRegistrar = FakeHotkeyRegistrar()
            let appBranchMonitor = AppBranchMonitor(
                workspace: TestAppBranchWorkspace(),
                callbackQueue: DispatchQueue(label: "com.stet.tests.sessioncontroller.action.appbranch.fallback")
            )

            let session = MacAppSessionController(
                workflowController: workflow,
                shellPresentationController: shell,
                permissionGateController: permissionGate,
                permissionManager: permissionManager,
                appBranchMonitor: appBranchMonitor,
                hotkeyRegistrar: hotkeyRegistrar
            )
            let presentationModel = FakePresentationModel()
            session.activate(presentationModel: presentationModel, showInDock: false)

            workflow.dictationViewModel.send(.transcriptionSucceeded("transcript"))

            #expect(
                await TestSupport.eventually {
                    workflow.dictationViewModel.state == .clipboardPending("transcript")
                })
            #expect(clipboardService.copiedTexts == ["transcript", "transcript"])
            #expect(textInjectionService.didRequestAccessIfNeeded == false)
            #expect(shell.isPanelVisible)
        }
    }

#endif
