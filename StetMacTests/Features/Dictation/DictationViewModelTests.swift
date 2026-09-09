import Foundation
import StetAI
import StetCore
import Testing

@testable import Stet

@MainActor
@Suite("Dictation View Model", .serialized)
struct DictationViewModelTests {
    private let fallbackDelay: Duration = .milliseconds(20)

    @Test(arguments: [0, 1, 2])
    func lateProcessingFailureDoesNotResetNewRecording(failureKind: Int) async throws {
        let speech = ControllableSpeechService()
        await speech.setStopBehavior(.suspended)
        await speech.setCancelFailsPendingStop(false)
        let history = HistoryRecordingSpy()
        let viewModel = DictationViewModel(speechService: speech, historyService: history)
        viewModel.startCapture()
        #require(await TestSupport.eventually { viewModel.state == .listening })
        viewModel.stopCapture()
        #require(await TestSupport.eventuallyAsync { await speech.counts().stop == 1 })
        viewModel.send(.resetTapped)
        // Deliberately restart in the same main-actor turn as reset.
        viewModel.startCapture { $0.uppercased() }
        #require(await TestSupport.eventually { viewModel.state == .listening })
        switch failureKind {
        case 0: await speech.failStop(with: CancellationError())
        case 1: await speech.failStop(with: SpeechServiceError.emptyTranscription)
        default: await speech.failStop(with: TestError.expected)
        }
        // Let the old task's catch run before testing the new session's stop path.
        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.state == .listening)
        await speech.setStopBehavior(.immediate("new"))
        viewModel.stopCapture()
        #expect(await TestSupport.eventually { viewModel.state == .result("NEW") })
        #expect(history.rawTexts == ["new"])
        #expect(history.llmTexts == ["NEW"])
    }

    @Test func cancelledTransformerCannotWriteIntoNewHistory() async throws {
        let speech = ControllableSpeechService()
        await speech.setStopBehavior(.immediate("old"))
        let gate = TestSuspensionGate()
        let history = HistoryRecordingSpy()
        let viewModel = DictationViewModel(speechService: speech, historyService: history)
        viewModel.startCapture { _ in
            await gate.wait()
            return "OLD"
        }
        #require(await TestSupport.eventually { viewModel.state == .listening })
        viewModel.stopCapture()
        #require(await TestSupport.eventuallyAsync { await gate.hasWaiter })
        viewModel.send(.resetTapped)
        viewModel.startCapture()
        #require(await TestSupport.eventually { viewModel.state == .listening })
        await gate.open()
        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.state == .listening)
        #expect(history.rawTexts.isEmpty)
        #expect(history.llmTexts.isEmpty)
        await speech.setStopBehavior(.immediate("new"))
        viewModel.stopCapture()
        #expect(await TestSupport.eventually { viewModel.state == .result("new") })
        #expect(history.rawTexts == ["new"])
    }

    @Test func lateExternalOperationFailureDoesNotResetNewRecording() async throws {
        let speech = ControllableSpeechService()
        let gate = TestSuspensionGate()
        let viewModel = DictationViewModel(speechService: speech)
        viewModel.runProcessingOperation {
            await gate.wait()
            throw CancellationError()
        }
        #require(await TestSupport.eventuallyAsync { await gate.hasWaiter })
        viewModel.send(.resetTapped)
        viewModel.startCapture()
        #require(await TestSupport.eventually { viewModel.state == .listening })
        await gate.open()
        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.state == .listening)
        viewModel.stopCapture()
        #expect(await TestSupport.eventually { viewModel.state == .result("transcript") })
    }

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

    @Test func recordsRawASRAndRewrittenTextSeparatelyInHistory() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(
            .immediate(
                SpeechTranscriptionResult(
                    rawText: "um hello world",
                    text: "Hello world.",
                    wasRewritten: true
                )
            )
        )
        let history = HistoryRecordingSpy()
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay,
            historyService: history
        )

        viewModel.startCapture()
        #expect(await TestSupport.eventually { viewModel.state == .listening })
        viewModel.stopCapture()
        #expect(await TestSupport.eventually { viewModel.state == .result("Hello world.") })

        #expect(history.rawTexts == ["um hello world"])
        #expect(history.llmTexts == ["Hello world."])
        #expect(history.commitCount == 1)
    }

    @Test func doesNotRecordLLMHistoryWhenRewriteDidNotRun() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(.immediate("plain transcript"))
        let history = HistoryRecordingSpy()
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay,
            historyService: history
        )

        viewModel.startCapture()
        #expect(await TestSupport.eventually { viewModel.state == .listening })
        viewModel.stopCapture()
        #expect(await TestSupport.eventually { viewModel.state == .result("plain transcript") })

        #expect(history.rawTexts == ["plain transcript"])
        #expect(history.llmTexts.isEmpty)
        #expect(history.commitCount == 1)
    }

    @Test func transformIsRecordedAsLLMHistoryEvenWithoutSpeechRewrite() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(.immediate("draft"))
        let history = HistoryRecordingSpy()
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay,
            historyService: history
        )

        viewModel.startCapture { text in
            text.uppercased()
        }
        viewModel.stopCapture()
        #expect(await TestSupport.eventually { viewModel.state == .result("DRAFT") })

        #expect(history.rawTexts == ["draft"])
        #expect(history.llmTexts == ["DRAFT"])
        #expect(history.commitCount == 1)
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

    @Test func resetDuringProcessingDiscardsLateTranscriptionResult() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(.suspended)
        await speechService.setCancelFailsPendingStop(false)
        let viewModel = DictationViewModel(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        viewModel.startCapture()
        #expect(await TestSupport.eventually { viewModel.state == .listening })

        viewModel.stopCapture()
        #expect(await TestSupport.eventually { viewModel.state == .processing })
        #expect(await TestSupport.eventuallyAsync { await speechService.counts().stop == 1 })

        viewModel.send(.resetTapped)
        #expect(viewModel.state == .idle)
        #expect(await TestSupport.eventuallyAsync { await speechService.counts().cancel == 1 })

        await speechService.finishStop(with: "should not be delivered")
        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.state == .idle)
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

@MainActor
private final class HistoryRecordingSpy: DictationHistoryRecording {
    var rawTexts: [String] = []
    var llmTexts: [String] = []
    var commitCount = 0

    func recordRaw(_ text: String) {
        rawTexts.append(text)
    }

    func recordLLM(_ text: String) {
        llmTexts.append(text)
    }

    func commitPending() -> UUID? {
        commitCount += 1
        return UUID()
    }
}
