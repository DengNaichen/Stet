#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    private final class TestMediaPlaybackController: MediaPlaybackControlling {
        private(set) var pauseCallCount = 0
        private(set) var resumeCallCount = 0

        func pausePlaybackIfNeeded() {
            pauseCallCount += 1
        }

        func resumePlaybackIfNeeded() {
            resumeCallCount += 1
        }
    }

    @MainActor
    private final class TestSystemAudioMuting: SystemAudioMuting {
        private(set) var activateCallCount = 0
        private(set) var restoreCallCount = 0

        func activateMuteIfNeeded() -> Bool {
            activateCallCount += 1
            return true
        }

        func restoreMuteIfNeeded() {
            restoreCallCount += 1
        }
    }

    @MainActor
    private final class TestInteractionSoundPlayer: InteractionSoundPlaying {
        private(set) var startPromptCallCount = 0
        private(set) var finishCallCount = 0
        private(set) var previewCallCount = 0
        var waitForPromptCompletion = false
        private var promptContinuation: CheckedContinuation<Void, Never>?
        private var shouldFinishPendingPrompt = false

        func playStartPrompt(preset _: InteractionSoundPreset) async {
            startPromptCallCount += 1
            guard waitForPromptCompletion else { return }

            if shouldFinishPendingPrompt {
                shouldFinishPendingPrompt = false
                return
            }

            await withCheckedContinuation { continuation in
                promptContinuation = continuation
            }
        }

        func playFinish(preset _: InteractionSoundPreset) {
            finishCallCount += 1
        }

        func playPreview(preset _: InteractionSoundPreset) {
            previewCallCount += 1
        }

        func finishPrompt() {
            if let promptContinuation {
                self.promptContinuation = nil
                promptContinuation.resume()
            } else {
                shouldFinishPendingPrompt = true
            }
        }
    }

    @MainActor
    @Suite("Mac Dictation Workflow Controller", .serialized)
    struct MacDictationWorkflowControllerTests {
        private func makeController(
            defaults: UserDefaults? = nil,
            speechService: ControllableSpeechService? = nil,
            textInjectionService: TestTextInjectionService? = nil,
            mediaPlaybackController: TestMediaPlaybackController? = nil,
            systemAudioMuting: TestSystemAudioMuting? = nil,
            interactionSoundPlayer: TestInteractionSoundPlayer? = nil,
            mediaResumeDelay: Duration = .zero
        ) -> (
            controller: MacDictationWorkflowController,
            viewModel: DictationViewModel,
            clipboard: TestClipboardService,
            textInjectionService: TestTextInjectionService,
            mediaPlaybackController: TestMediaPlaybackController,
            systemAudioMuting: TestSystemAudioMuting?,
            interactionSoundPlayer: TestInteractionSoundPlayer
        ) {
            let defaults = defaults ?? TestSupport.makeUserDefaults()
            let speechService = speechService ?? ControllableSpeechService()
            let textInjectionService = textInjectionService ?? TestTextInjectionService()
            let mediaPlaybackController = mediaPlaybackController ?? TestMediaPlaybackController()
            let systemAudioMuting = systemAudioMuting
            let interactionSoundPlayer = interactionSoundPlayer ?? TestInteractionSoundPlayer()
            if defaults.object(forKey: MacPreferences.interactionSoundsEnabled) == nil {
                defaults.set(false, forKey: MacPreferences.interactionSoundsEnabled)
            }
            let settingsStore = DictationSettingsStore(
                defaults: defaults,
                secretStore: TestSecretStore()
            )
            let viewModel = DictationViewModel(speechService: speechService)
            let clipboard = TestClipboardService()
            let captureCoordinator = MacDictationCaptureCoordinator(
                clipboardService: clipboard,
                textInjectionService: textInjectionService
            )

            let controller = MacDictationWorkflowController(
                dictationViewModel: viewModel,
                captureCoordinator: captureCoordinator,
                textInjectionService: textInjectionService,
                mediaPlaybackController: mediaPlaybackController,
                systemAudioMuting: systemAudioMuting,
                settingsStore: settingsStore,
                interactionSoundPlayer: interactionSoundPlayer,
                mediaResumeDelay: mediaResumeDelay
            )

            return (
                controller: controller,
                viewModel: viewModel,
                clipboard: clipboard,
                textInjectionService: textInjectionService,
                mediaPlaybackController: mediaPlaybackController,
                systemAudioMuting: systemAudioMuting,
                interactionSoundPlayer: interactionSoundPlayer
            )
        }

        @Test func startDictationCaptureShowsPanelAndStartsListening() async {
            let subject = makeController()
            var showPanelCount = 0

            subject.controller.startDictationCapture(source: .interface) {
                showPanelCount += 1
            }

            #expect(showPanelCount == 1)
            #expect(subject.controller.activeWorkflow == .dictation)
            #expect(subject.viewModel.state.isCaptureInFlight)
            #expect(await TestSupport.eventually { subject.viewModel.state == .listening })
            #expect(subject.controller.statusText == "Listening...")

            guard case .interface? = subject.controller.activeRecordingSource else {
                Issue.record("Expected interface recording source")
                return
            }

            subject.viewModel.send(.resetTapped)
        }

        @Test func processingStatusTextReflectsProviderAndRewriteSetting() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(DictationProvider.groq.rawValue, forKey: MacPreferences.transcriptionProvider)
            defaults.set(true, forKey: MacPreferences.rewriteEnabled)
            let subject = makeController(defaults: defaults)

            #expect(subject.controller.processingStatusText == "Transcribing with Groq and rewriting...")

            defaults.set(false, forKey: MacPreferences.rewriteEnabled)
            #expect(subject.controller.processingStatusText == "Transcribing with Groq...")
        }

        @Test func stateTransitionsPauseAndResumeMediaWhenConfigured() async {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.pauseMediaDuringDictation)
            let speechService = ControllableSpeechService()
            await speechService.setStopBehavior(.suspended)
            let subject = makeController(
                defaults: defaults,
                speechService: speechService
            )

            subject.controller.startDictationCapture(source: .hotkey) {}
            #expect(subject.mediaPlaybackController.pauseCallCount == 1)
            #expect(await TestSupport.eventually { subject.viewModel.state == .listening })

            subject.viewModel.send(.stopTapped)
            subject.controller.handleStateTransition(from: .listening, to: .processing)

            #expect(
                await TestSupport.eventually {
                    subject.mediaPlaybackController.resumeCallCount == 1
                })
            #expect(subject.controller.activeRecordingSource == nil)

            subject.viewModel.send(.resetTapped)
        }

        @Test func stateTransitionsActivateAndRestoreSystemAudioMuteWhenConfigured() async {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.pauseMediaDuringDictation)
            let speechService = ControllableSpeechService()
            await speechService.setStopBehavior(.suspended)
            let systemAudioMuting = TestSystemAudioMuting()
            let subject = makeController(
                defaults: defaults,
                speechService: speechService,
                systemAudioMuting: systemAudioMuting
            )

            subject.controller.startDictationCapture(source: .hotkey) {}
            #expect(systemAudioMuting.activateCallCount == 0)
            #expect(await TestSupport.eventually { subject.viewModel.state == .listening })
            #expect(await TestSupport.eventually { systemAudioMuting.activateCallCount == 1 })

            subject.viewModel.send(.stopTapped)
            subject.controller.handleStateTransition(from: .listening, to: .processing)

            #expect(
                await TestSupport.eventually {
                    systemAudioMuting.restoreCallCount == 1
                })

            subject.viewModel.send(.resetTapped)
        }

        @Test func completedDictationUsesCaptureCoordinatorPath() async {
            let textInjectionService = TestTextInjectionService()
            textInjectionService.pasteResult = true
            let subject = makeController(textInjectionService: textInjectionService)
            var showPanelCount = 0

            let outcome = await subject.controller.handleCompletedResult(
                text: "hello",
                workflow: .dictation
            ) {
                showPanelCount += 1
            }

            #expect(outcome == .completed)
            #expect(subject.clipboard.copiedTexts == ["hello"])
            #expect(subject.textInjectionService.pasteTargets.count == 1)
            #expect(showPanelCount == 0)
        }

        @Test func failedSelectionReplacementRequestsAccessWithoutRevealingPanel() async {
            let textInjectionService = TestTextInjectionService()
            textInjectionService.isAvailable = false
            textInjectionService.accessState = .init(
                hasAccessibilityAccess: false,
                hasPostEventAccess: false
            )
            textInjectionService.pasteResult = false
            let subject = makeController(textInjectionService: textInjectionService)
            var showPanelCount = 0

            let outcome = await subject.controller.handleCompletedResult(
                text: "rewritten",
                workflow: .rewriteFromSelection(sourceText: "hello")
            ) {
                showPanelCount += 1
            }

            #expect(outcome == .clipboardPending)
            #expect(subject.textInjectionService.replacementTexts == ["rewritten"])
            #expect(subject.textInjectionService.didRequestAccessIfNeeded)
            #expect(showPanelCount == 0)
        }

        @Test func resetWorkflowIfNeededNoopWhenSourceIsActive() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.pauseMediaDuringDictation)
            let subject = makeController(defaults: defaults)

            subject.controller.startDictationCapture(source: .hotkey) {}

            subject.controller.resetWorkflowIfNeeded()

            #expect(subject.controller.activeWorkflow == .dictation)
            #expect(subject.controller.activeRecordingSource == .hotkey)
        }

        @Test func resetWorkflowIfNeededResetsWhenNoSource() {
            let subject = makeController()
            subject.controller.startDictationCapture(source: .hotkey) {}
            subject.controller.stopActiveCapture()

            subject.controller.resetWorkflowIfNeeded()

            #expect(subject.controller.activeWorkflow == .dictation)
            #expect(subject.controller.activeRecordingSource == nil)
        }

        @Test func copyPendingResultToClipboardForwardsText() {
            let subject = makeController()

            subject.controller.copyPendingResultToClipboard("needs-review")

            #expect(subject.clipboard.copiedTexts == ["needs-review"])
        }

        @Test func statusTextReflectsDictationStateTransitions() async {
            let subject = makeController()

            #expect(subject.controller.statusText == "Ready")

            subject.controller.startDictationCapture(source: .interface) {}
            #expect(subject.controller.statusText == "Starting microphone...")
            #expect(await TestSupport.eventually { subject.viewModel.state == .listening })
            #expect(subject.controller.statusText == "Listening...")

            subject.viewModel.send(.stopTapped)
            #expect(subject.controller.statusText == "Processing...")

            subject.viewModel.send(.transcriptionSucceeded("hello"))
            #expect(subject.controller.statusText == "Transcription complete")

            subject.viewModel.send(.clipboardPending("hello"))
            #expect(subject.controller.statusText == "Copy to clipboard")

            subject.viewModel.send(.transcriptionFailed(.network(code: .notConnectedToInternet, message: "Offline")))
            #expect(subject.controller.statusText == "Network problem")
        }

        @Test func listeningToProcessingTransitionResumesPlaybackImmediately() async {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.pauseMediaDuringDictation)
            let speechService = ControllableSpeechService()
            await speechService.setStopBehavior(.suspended)
            let subject = makeController(
                defaults: defaults,
                speechService: speechService
            )

            subject.controller.startDictationCapture(source: .interface) {}
            #expect(subject.mediaPlaybackController.pauseCallCount == 1)
            #expect(await TestSupport.eventually { subject.viewModel.state == .listening })

            subject.viewModel.send(.stopTapped)
            subject.controller.handleStateTransition(from: .listening, to: .processing)

            #expect(subject.mediaPlaybackController.pauseCallCount == 1)
            #expect(
                await TestSupport.eventually {
                    subject.mediaPlaybackController.resumeCallCount == 1
                })
        }

        @Test func processingToResultTransitionDoesNotResumePlaybackAgain() async {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.pauseMediaDuringDictation)
            let speechService = ControllableSpeechService()
            await speechService.setStopBehavior(.suspended)
            let subject = makeController(
                defaults: defaults,
                speechService: speechService
            )

            subject.controller.startDictationCapture(source: .interface) {}
            #expect(subject.mediaPlaybackController.pauseCallCount == 1)
            #expect(await TestSupport.eventually { subject.viewModel.state == .listening })

            subject.viewModel.send(.stopTapped)
            subject.controller.handleStateTransition(from: .listening, to: .processing)
            #expect(
                await TestSupport.eventually {
                    subject.mediaPlaybackController.resumeCallCount == 1
                })

            subject.viewModel.send(.transcriptionSucceeded("done"))
            subject.controller.handleStateTransition(from: .processing, to: .result("done"))

            #expect(subject.mediaPlaybackController.pauseCallCount == 1)
            #expect(subject.mediaPlaybackController.resumeCallCount == 1)
        }

        @Test func listeningToProcessingTransitionDefersResumeUntilConfiguredDelayElapses() async {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.pauseMediaDuringDictation)
            let speechService = ControllableSpeechService()
            await speechService.setStopBehavior(.suspended)
            let subject = makeController(
                defaults: defaults,
                speechService: speechService,
                mediaResumeDelay: .milliseconds(120)
            )

            subject.controller.startDictationCapture(source: .interface) {}
            #expect(subject.mediaPlaybackController.pauseCallCount == 1)
            #expect(await TestSupport.eventually { subject.viewModel.state == .listening })

            subject.viewModel.send(.stopTapped)
            subject.controller.handleStateTransition(from: .listening, to: .processing)

            #expect(subject.mediaPlaybackController.pauseCallCount == 1)
            #expect(subject.mediaPlaybackController.resumeCallCount == 0)
            #expect(
                await TestSupport.eventually(timeout: .milliseconds(400)) {
                    subject.mediaPlaybackController.resumeCallCount == 1
                })
        }

        @Test func processingToResultTransitionDoesNotCancelDeferredResume() async {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.pauseMediaDuringDictation)
            let speechService = ControllableSpeechService()
            await speechService.setStopBehavior(.suspended)
            let subject = makeController(
                defaults: defaults,
                speechService: speechService,
                mediaResumeDelay: .milliseconds(120)
            )

            subject.controller.startDictationCapture(source: .interface) {}
            #expect(subject.mediaPlaybackController.pauseCallCount == 1)
            #expect(await TestSupport.eventually { subject.viewModel.state == .listening })

            subject.viewModel.send(.stopTapped)
            subject.controller.handleStateTransition(from: .listening, to: .processing)

            subject.viewModel.send(.transcriptionSucceeded("done"))
            subject.controller.handleStateTransition(from: .processing, to: .result("done"))

            #expect(subject.mediaPlaybackController.resumeCallCount == 0)
            #expect(
                await TestSupport.eventually(timeout: .milliseconds(400)) {
                    subject.mediaPlaybackController.resumeCallCount == 1
                })
        }

        @Test func finishSoundPlaysAsSoonAsCaptureStopsWhileTranscriptionIsStillProcessing() async {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.interactionSoundsEnabled)
            let speechService = ControllableSpeechService()
            await speechService.setStopBehavior(.suspended)
            let interactionSoundPlayer = TestInteractionSoundPlayer()
            let subject = makeController(
                defaults: defaults,
                speechService: speechService,
                interactionSoundPlayer: interactionSoundPlayer
            )

            subject.controller.startDictationCapture(source: .interface) {}
            #expect(await TestSupport.eventually { subject.viewModel.state == .listening })

            subject.controller.stopActiveCapture()

            #expect(
                await TestSupport.eventually {
                    subject.viewModel.state == .processing && subject.interactionSoundPlayer.finishCallCount == 1
                })

            subject.controller.handleStateTransition(from: .listening, to: .processing)
            #expect(subject.interactionSoundPlayer.finishCallCount == 1)

            await speechService.finishStop(with: "done")
            #expect(
                await TestSupport.eventually {
                    if case .result("done") = subject.viewModel.state {
                        return true
                    }
                    return false
                })

            subject.controller.handleStateTransition(from: .processing, to: .result("done"))
            #expect(subject.interactionSoundPlayer.finishCallCount == 1)
        }

        @Test func promptPlaybackRunsInParallelWithWarmupAndDelaysListeningUntilCompletion() async {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.pauseMediaDuringDictation)
            defaults.set(true, forKey: MacPreferences.interactionSoundsEnabled)
            let speechService = ControllableSpeechService()
            await speechService.setActivationBehavior(.suspended)
            let interactionSoundPlayer = TestInteractionSoundPlayer()
            interactionSoundPlayer.waitForPromptCompletion = true
            let subject = makeController(
                defaults: defaults,
                speechService: speechService,
                interactionSoundPlayer: interactionSoundPlayer
            )

            subject.controller.startDictationCapture(source: .hotkey) {}

            #expect(subject.mediaPlaybackController.pauseCallCount == 1)
            #expect(
                await TestSupport.eventually(timeout: .seconds(3)) {
                    subject.viewModel.state == .starting && subject.viewModel.recordingLevel > 0
                })
            #expect(await speechService.counts().activate == 0)

            interactionSoundPlayer.finishPrompt()
            #expect(
                await TestSupport.eventuallyAsync(timeout: .seconds(3)) { await speechService.counts().activate == 1 })
            #expect(subject.viewModel.state == .starting)

            await speechService.allowActivation()
            #expect(await TestSupport.eventually(timeout: .seconds(3)) { subject.viewModel.state == .listening })
        }

        @Test func promptPlaybackTimeoutStillActivatesCapture() async {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.interactionSoundsEnabled)
            let speechService = ControllableSpeechService()
            await speechService.setActivationBehavior(.suspended)
            let interactionSoundPlayer = TestInteractionSoundPlayer()
            interactionSoundPlayer.waitForPromptCompletion = true
            let subject = makeController(
                defaults: defaults,
                speechService: speechService,
                interactionSoundPlayer: interactionSoundPlayer
            )

            subject.controller.startDictationCapture(source: .interface) {}

            #expect(
                await TestSupport.eventuallyAsync(timeout: .seconds(2)) {
                    await speechService.counts().activate == 1
                })
            #expect(subject.viewModel.state == .starting)

            await speechService.allowActivation()
            #expect(await TestSupport.eventually(timeout: .seconds(3)) { subject.viewModel.state == .listening })
        }
    }
#endif
