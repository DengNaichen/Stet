import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Dictation View Model", .serialized)
struct DictationViewModelTests {
    private let fallbackDelay: Duration = .milliseconds(20)

    @Test func startAndStopCaptureProducesResult() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(.immediate("hello world"))
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        viewModel.startCapture()
        #expect(viewModel.state == .starting)
        #expect(await TestSupport.eventually { viewModel.state == .listening })

        viewModel.stopCapture()
        #expect(await TestSupport.eventually { viewModel.state == .result("hello world") })

        #expect(viewModel.state == .result("hello world"))
        #expect(await speechService.counts().stop == 1)
        #expect(await speechService.counts().activate == 1)
    }

    @Test func stopWhileStartIsPendingDefersProcessingUntilCaptureActuallyStarts() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStartBehavior(.suspended)
        await speechService.setStopBehavior(.suspended)
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        viewModel.startCapture()
        viewModel.stopCapture()
        #expect(viewModel.state == .starting)

        #expect(await TestSupport.eventuallyAsync { await speechService.counts().start == 1 })
        await speechService.allowStart()
        #expect(await TestSupport.eventually { viewModel.state == .processing })
        #expect(await TestSupport.eventuallyAsync { await speechService.counts().stop == 1 })
        await speechService.finishStop(with: "completed")
        #expect(await TestSupport.eventually { viewModel.state == .result("completed") })

        #expect(viewModel.state == .result("completed"))
        #expect(await speechService.counts().start == 1)
        #expect(await speechService.counts().activate == 1)
        #expect(await speechService.counts().stop == 1)
    }

    @Test func transformIsAppliedBeforePublishingResult() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(.immediate("draft"))
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        viewModel.startCapture { text in
            text.uppercased()
        }
        viewModel.stopCapture()
        #expect(await TestSupport.eventually { viewModel.state == .result("DRAFT") })

        #expect(viewModel.state == .result("DRAFT"))
    }

    @Test func resetCancelsActiveRecordingAndReturnsToIdle() async {
        let speechService = ControllableSpeechService()
        await speechService.setStartBehavior(.suspended)
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        viewModel.startCapture()
        viewModel.send(.resetTapped)
        await Task.yield()

        #expect(viewModel.state == .idle)
        #expect(await speechService.counts().cancel == 1)
    }

    @Test func explicitActivationKeepsViewModelStartingUntilActivated() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setActivationBehavior(.suspended)
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        viewModel.startCapture(activateWhenReady: false)
        #expect(await TestSupport.eventuallyAsync { await speechService.counts().start == 1 })
        #expect(viewModel.state == .starting)

        viewModel.activateCaptureWindow()
        #expect(await TestSupport.eventuallyAsync { await speechService.counts().activate == 1 })
        #expect(viewModel.state == .starting)

        await speechService.allowActivation()
        #expect(await TestSupport.eventually { viewModel.state == .listening })
    }

    @Test func pendingActivationDuringStartupActivatesOnceStartCompletes() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStartBehavior(.suspended)
        await speechService.setActivationBehavior(.suspended)
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        viewModel.startCapture(activateWhenReady: false)
        viewModel.activateCaptureWindow()

        #expect(viewModel.state == .starting)
        #expect(await speechService.counts().activate == 0)

        #expect(
            await TestSupport.eventuallyAsync(timeout: .seconds(5)) {
                await speechService.counts().start == 1
            })
        await speechService.allowStart()

        #expect(
            await TestSupport.eventuallyAsync(timeout: .seconds(5)) {
                await speechService.counts().activate == 1
            })
        await speechService.allowActivation()

        #expect(await TestSupport.eventually(timeout: .seconds(5)) { viewModel.state == .listening })
        #expect(await speechService.counts().start == 1)
        #expect(await speechService.counts().activate == 1)
    }

    @Test func manualActivationFallbackActivatesCaptureIfControllerNeverSignals() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setActivationBehavior(.suspended)
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        viewModel.startCapture(activateWhenReady: false)

        #expect(viewModel.state == .starting)
        #expect(
            await TestSupport.eventuallyAsync(timeout: .seconds(8)) {
                await speechService.counts().activate == 1
            })
        await speechService.allowActivation()

        #expect(await TestSupport.eventually(timeout: .seconds(8)) { viewModel.state == .listening })
        #expect(await speechService.counts().start == 1)
        #expect(await speechService.counts().activate == 1)
    }

    @Test func processingOperationFailurePublishesError() async {
        let speechService = ControllableSpeechService()
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        viewModel.runProcessingOperation {
            throw TestError.expected
        }
        await Task.yield()

        #expect(viewModel.state == .error(.unknown(message: TestError.expected.localizedDescription)))
    }

    @Test func clipboardPendingActionPublishesClipboardPendingState() {
        let speechService = ControllableSpeechService()
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        viewModel.send(.clipboardPending("hello"))

        #expect(viewModel.state == .clipboardPending("hello"))
    }

    @Test func startFailurePublishesStructuredFailure() async {
        let speechService = ControllableSpeechService()
        await speechService.setStartBehavior(.fail(SpeechServiceError.microphonePermissionDenied))
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        viewModel.startCapture()

        #expect(
            await TestSupport.eventually {
                viewModel.state == .error(.microphonePermissionDenied)
            })
    }

    @Test func stopFailurePreservesStructuredProviderFailure() async {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(.fail(OpenAIError.missingAPIKey(provider: .groq)))
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        viewModel.startCapture()
        #expect(await TestSupport.eventually { viewModel.state == .listening })

        viewModel.stopCapture()

        #expect(
            await TestSupport.eventually {
                viewModel.state == .error(.missingAPIKey(provider: .groq))
            })
    }

    @Test func stopFailurePreservesStepAwareProviderConfigurationFailure() async {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(
            .fail(
                ProviderConfigurationError.missingRequirements([
                    ProviderConfigurationRequirement(step: .transcription, provider: .groq),
                    ProviderConfigurationRequirement(step: .rewrite, provider: .openAI),
                ])
            )
        )
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        viewModel.startCapture()
        #expect(await TestSupport.eventually { viewModel.state == .listening })

        viewModel.stopCapture()

        #expect(
            await TestSupport.eventually {
                viewModel.state
                    == .error(
                        .missingProviderConfiguration(
                            requirements: [
                                ProviderConfigurationRequirement(step: .transcription, provider: .groq),
                                ProviderConfigurationRequirement(step: .rewrite, provider: .openAI),
                            ]
                        )
                    )
            })
    }

    @Test func stopFailurePreservesUnsupportedProviderPairFailure() async {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(
            .fail(
                DictationFailure.unsupportedProviderCombination(
                    transcriptionProvider: .openAI,
                    rewriteProvider: .groq
                )
            )
        )
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        viewModel.startCapture()
        #expect(await TestSupport.eventually { viewModel.state == .listening })

        viewModel.stopCapture()

        #expect(
            await TestSupport.eventually {
                viewModel.state
                    == .error(
                        .unsupportedProviderCombination(
                            transcriptionProvider: .openAI,
                            rewriteProvider: .groq
                        )
                    )
            })
    }

    @Test func emptyTranscriptionReturnsToIdleWithoutPublishingError() async {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(.fail(SpeechServiceError.emptyTranscription))
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        viewModel.startCapture()
        #expect(await TestSupport.eventually { viewModel.state == .listening })

        viewModel.stopCapture()

        #expect(await TestSupport.eventually { viewModel.state == .idle })
    }

}
