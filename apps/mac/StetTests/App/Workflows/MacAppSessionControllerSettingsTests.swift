#if os(macOS)
    import Combine
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    private final class TestShellPresenter: MacShellPresenting {
        var onVisibilityChange: (() -> Void)?
        private(set) var isPanelVisible = false
        private(set) var applyDockVisibilityCalls: [Bool] = []
        private(set) var openSettingsCalls: [Bool] = []
        private(set) var settingsDidAppearCalls: [Bool] = []
        private(set) var settingsDidDisappearCalls: [Bool] = []
        private(set) var cancelScheduledPanelHideCount = 0
        private(set) var schedulePanelHideCallCount = 0
        private(set) var showPanelCallCount = 0
        private(set) var showTransientPanelCallCount = 0
        private(set) var hidePanelCallCount = 0
        private(set) var togglePanelCallCount = 0

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
            isPanelVisible = false
            onVisibilityChange?()
        }

        func cancelScheduledPanelHide() {
            cancelScheduledPanelHideCount += 1
        }

        func scheduleTransientPanelHideIfNeeded(currentState: @escaping @MainActor () -> DictationState) {
            schedulePanelHideCallCount += 1
        }

        func applyDockVisibility(showInDock: Bool) {
            applyDockVisibilityCalls.append(showInDock)
        }

        func openSettings(currentShowInDockPreference: Bool, using action: () -> Void) {
            openSettingsCalls.append(currentShowInDockPreference)
            action()
        }

        func settingsDidAppear(currentShowInDockPreference: Bool) {
            settingsDidAppearCalls.append(currentShowInDockPreference)
        }

        func settingsDidDisappear(currentShowInDockPreference: Bool) {
            settingsDidDisappearCalls.append(currentShowInDockPreference)
        }
    }

    @MainActor
    private final class TestPermissionGatePresenter: MacPermissionGatePresenting {
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
    private final class TestHotkeyRegistrar: MacDictationHotkeyRegistering {
        private(set) var clearHandlersCallCount = 0
        private(set) var registerKeyDownCallCount = 0
        private(set) var registerKeyUpCallCount = 0

        func clearDictationHandlers() {
            clearHandlersCallCount += 1
        }

        func registerDictationKeyDown(_ handler: @escaping () -> Void) {
            registerKeyDownCallCount += 1
        }

        func registerDictationKeyUp(_ handler: @escaping () -> Void) {
            registerKeyUpCallCount += 1
        }
    }

    @MainActor
    private final class TestMediaPlaybackController: MediaPlaybackControlling {
        func pausePlaybackIfNeeded() {}

        func resumePlaybackIfNeeded() {}
    }

    private final class TestAppBranchWorkspace: AppBranchWorkspaceObserving {
        var frontmostApplication: AppBranchWorkspaceApplicationSnapshot?

        func observeFrontmostApplicationChanges(_ handler: @escaping () -> Void) -> AppBranchWorkspaceObservationToken {
            AppBranchWorkspaceObservationToken(observer: NSObject())
        }

        func removeObservation(_ token: AppBranchWorkspaceObservationToken) {}
    }

    @MainActor
    @Suite("Mac App Session Controller Settings", .serialized)
    struct MacAppSessionControllerSettingsTests {
        private func makeSut(
            defaults: UserDefaults,
            textInjectionService: TestTextInjectionService
        ) -> (
            sessionController: MacAppSessionController,
            workflowController: MacDictationWorkflowController,
            shellPresenter: TestShellPresenter,
            permissionGatePresenter: TestPermissionGatePresenter,
            hotkeyRegistrar: TestHotkeyRegistrar
        ) {
            let shellPresenter = TestShellPresenter()
            let permissionGatePresenter = TestPermissionGatePresenter()
            let hotkeyRegistrar = TestHotkeyRegistrar()

            let speechService = ControllableSpeechService()
            let dictationViewModel = DictationViewModel(speechService: speechService)
            let clipboardService = TestClipboardService()
            let captureCoordinator = MacDictationCaptureCoordinator(
                clipboardService: clipboardService,
                textInjectionService: textInjectionService
            )
            let settingsStore = DictationSettingsStore(
                defaults: defaults,
                secretStore: TestSecretStore()
            )
            let workflowController = MacDictationWorkflowController(
                dictationViewModel: dictationViewModel,
                captureCoordinator: captureCoordinator,
                textInjectionService: textInjectionService,
                mediaPlaybackController: TestMediaPlaybackController(),
                settingsStore: settingsStore,
                interactionSoundPlayer: InteractionSoundPlayer(),
                mediaResumeDelay: .zero
            )
            let permissionManager = MacPermissionManager(textInjectionService: textInjectionService)
            let appBranchMonitor = AppBranchMonitor(
                workspace: TestAppBranchWorkspace(),
                callbackQueue: DispatchQueue(label: "com.stet.tests.sessioncontroller.settings.appbranch")
            )

            let sessionController = MacAppSessionController(
                workflowController: workflowController,
                shellPresentationController: shellPresenter,
                permissionGateController: permissionGatePresenter,
                permissionManager: permissionManager,
                appBranchMonitor: appBranchMonitor,
                defaults: defaults,
                notificationCenter: NotificationCenter(),
                hotkeyRegistrar: hotkeyRegistrar
            )

            return (
                sessionController: sessionController,
                workflowController: workflowController,
                shellPresenter: shellPresenter,
                permissionGatePresenter: permissionGatePresenter,
                hotkeyRegistrar: hotkeyRegistrar
            )
        }

        @Test func applyDockVisibilityForwardsValueToPresentationController() {
            let defaults = TestSupport.makeUserDefaults()
            let textInjectionService = TestTextInjectionService()
            let (sut, _, shellPresenter, _, _) = makeSut(
                defaults: defaults,
                textInjectionService: textInjectionService
            )

            sut.applyDockVisibility(showInDock: true)
            sut.applyDockVisibility(showInDock: false)

            #expect(shellPresenter.applyDockVisibilityCalls == [true, false])
        }

        @Test func openSettingsForwardsCurrentPreferenceAndRunsAction() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.showInDock)
            let textInjectionService = TestTextInjectionService()
            let (sut, _, shellPresenter, _, _) = makeSut(
                defaults: defaults,
                textInjectionService: textInjectionService
            )
            var actionDidRun = false

            sut.openSettings {
                actionDidRun = true
            }

            #expect(shellPresenter.openSettingsCalls == [true])
            #expect(actionDidRun)
        }

        @Test func settingsDidAppearForwardsCurrentPreference() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(false, forKey: MacPreferences.showInDock)
            let textInjectionService = TestTextInjectionService()
            let (sut, _, shellPresenter, _, _) = makeSut(
                defaults: defaults,
                textInjectionService: textInjectionService
            )

            sut.settingsDidAppear()

            #expect(shellPresenter.settingsDidAppearCalls == [false])
        }

        @Test func settingsDidDisappearForwardsCurrentPreference() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.showInDock)
            let textInjectionService = TestTextInjectionService()
            let (sut, _, shellPresenter, _, _) = makeSut(
                defaults: defaults,
                textInjectionService: textInjectionService
            )

            sut.settingsDidDisappear()

            #expect(shellPresenter.settingsDidDisappearCalls == [true])
        }

        @Test func refreshRuntimeFromSettingsAppliesDockSettingAndNotifiesChange() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.showInDock)
            let textInjectionService = TestTextInjectionService()
            let (sut, _, shellPresenter, _, _) = makeSut(
                defaults: defaults,
                textInjectionService: textInjectionService
            )
            var onChangeCount = 0
            sut.onChange = {
                onChangeCount += 1
            }

            sut.refreshRuntimeFromSettings()

            #expect(shellPresenter.applyDockVisibilityCalls == [true])
            #expect(onChangeCount == 1)
        }

        @Test func finishOnboardingPersistsSelectedAppearanceTheme() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(false, forKey: MacPreferences.onboardingCompleted)
            let textInjectionService = TestTextInjectionService()
            let (sut, _, _, _, _) = makeSut(
                defaults: defaults,
                textInjectionService: textInjectionService
            )

            sut.selectOnboardingAppearanceTheme(.autumn)
            sut.finishOnboarding()

            #expect(defaults.bool(forKey: MacPreferences.onboardingCompleted))
            #expect(
                defaults.string(forKey: MacPreferences.shaderTheme)
                    == MacDictationVisualTheme.autumn.rawValue
            )
        }

        @Test func disablingDebugForceOnboardingRestoresCompletedOnboardingInDebugBuilds() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(false, forKey: MacPreferences.onboardingCompleted)
            defaults.set(true, forKey: MacPreferences.debugForceOnboarding)
            let textInjectionService = TestTextInjectionService()
            let (sut, _, _, _, _) = makeSut(
                defaults: defaults,
                textInjectionService: textInjectionService
            )

            sut.setDebugForceOnboardingEnabled(false)

            #expect(defaults.bool(forKey: MacPreferences.debugForceOnboarding) == false)
            #expect(defaults.bool(forKey: MacPreferences.onboardingCompleted))
            #expect(sut.onboardingStep == .done)
        }
    }
#endif
