import Foundation
import StetAI
import StetCore
import Testing

@testable import Stet

@MainActor
@Suite("Dictation Session", .serialized)
struct DictationSessionTests {
    private let fallbackDelay: Duration = .milliseconds(20)

    @Test(arguments: [0, 1, 2])
    func lateProcessingFailureDoesNotResetNewRecording(failureKind: Int) async throws {
        let speech = ControllableSpeechService()
        await speech.setStopBehavior(.suspended)
        await speech.setCancelFailsPendingStop(false)
        let history = HistoryRecordingSpy()
        let session = DictationSession(speechService: speech, historyService: history)
        session.startCapture()
        try #require(await TestSupport.eventually { session.state == .listening })
        session.stopCapture()
        try #require(await TestSupport.eventuallyAsync { await speech.counts().stop == 1 })
        session.cancel()
        // Deliberately restart in the same main-actor turn as reset.
        session.startCapture { $0.uppercased() }
        try #require(await TestSupport.eventually { session.state == .listening })
        switch failureKind {
        case 0: await speech.failStop(with: CancellationError())
        case 1: await speech.failStop(with: SpeechServiceError.emptyTranscription)
        default: await speech.failStop(with: TestError.expected)
        }
        // Let the old task's catch run before testing the new session's stop path.
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.state == .listening)
        await speech.setStopBehavior(.immediate("new"))
        session.stopCapture()
        #expect(await TestSupport.eventually { session.state == .result("NEW") })
        #expect(history.rawTexts == ["new"])
        #expect(history.llmTexts == ["NEW"])
    }

    @Test func cancelledTransformerCannotWriteIntoNewHistory() async throws {
        let speech = ControllableSpeechService()
        await speech.setStopBehavior(.immediate("old"))
        let gate = TestSuspensionGate()
        let history = HistoryRecordingSpy()
        let session = DictationSession(speechService: speech, historyService: history)
        session.startCapture { _ in
            await gate.wait()
            return "OLD"
        }
        try #require(await TestSupport.eventually { session.state == .listening })
        session.stopCapture()
        try #require(await TestSupport.eventuallyAsync { await gate.hasWaiter })
        session.cancel()
        session.startCapture()
        try #require(await TestSupport.eventually { session.state == .listening })
        await gate.open()
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.state == .listening)
        #expect(history.rawTexts.isEmpty)
        #expect(history.llmTexts.isEmpty)
        await speech.setStopBehavior(.immediate("new"))
        session.stopCapture()
        #expect(await TestSupport.eventually { session.state == .result("new") })
        #expect(history.rawTexts == ["new"])
    }

    @Test func startAndStopCaptureProducesResult() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(.immediate("hello world"))
        let session = DictationSession(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        session.startCapture()
        #expect(session.state == .starting)
        #expect(await TestSupport.eventually { session.state == .listening })

        session.stopCapture()
        #expect(await TestSupport.eventually { session.state == .result("hello world") })

        #expect(session.state == .result("hello world"))
        #expect(await speechService.counts().stop == 1)
        #expect(await speechService.counts().activate == 1)
    }

    @Test func stopWhileStartIsPendingDefersProcessingUntilCaptureActuallyStarts() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStartBehavior(.suspended)
        await speechService.setStopBehavior(.suspended)
        let session = DictationSession(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        session.startCapture()
        session.stopCapture()
        #expect(session.state == .starting)

        #expect(await TestSupport.eventuallyAsync { await speechService.counts().start == 1 })
        await speechService.allowStart()
        #expect(await TestSupport.eventually { session.state == .processing })
        #expect(await TestSupport.eventuallyAsync { await speechService.counts().stop == 1 })
        await speechService.finishStop(with: "completed")
        #expect(await TestSupport.eventually { session.state == .result("completed") })

        #expect(session.state == .result("completed"))
        #expect(await speechService.counts().start == 1)
        #expect(await speechService.counts().activate == 1)
        #expect(await speechService.counts().stop == 1)
    }

    @Test func transformIsAppliedBeforePublishingResult() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(.immediate("draft"))
        let session = DictationSession(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        session.startCapture { text in
            text.uppercased()
        }
        session.stopCapture()
        #expect(await TestSupport.eventually { session.state == .result("DRAFT") })

        #expect(session.state == .result("DRAFT"))
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
        let session = DictationSession(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay,
            historyService: history
        )

        session.startCapture()
        #expect(await TestSupport.eventually { session.state == .listening })
        session.stopCapture()
        #expect(await TestSupport.eventually { session.state == .result("Hello world.") })

        #expect(history.rawTexts == ["um hello world"])
        #expect(history.llmTexts == ["Hello world."])
        #expect(history.commitCount == 1)
    }

    @Test func doesNotRecordLLMHistoryWhenRewriteDidNotRun() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(.immediate("plain transcript"))
        let history = HistoryRecordingSpy()
        let session = DictationSession(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay,
            historyService: history
        )

        session.startCapture()
        #expect(await TestSupport.eventually { session.state == .listening })
        session.stopCapture()
        #expect(await TestSupport.eventually { session.state == .result("plain transcript") })

        #expect(history.rawTexts == ["plain transcript"])
        #expect(history.llmTexts.isEmpty)
        #expect(history.commitCount == 1)
    }

    @Test func transformIsRecordedAsLLMHistoryEvenWithoutSpeechRewrite() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(.immediate("draft"))
        let history = HistoryRecordingSpy()
        let session = DictationSession(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay,
            historyService: history
        )

        session.startCapture { text in
            text.uppercased()
        }
        session.stopCapture()
        #expect(await TestSupport.eventually { session.state == .result("DRAFT") })

        #expect(history.rawTexts == ["draft"])
        #expect(history.llmTexts == ["DRAFT"])
        #expect(history.commitCount == 1)
    }

    @Test func resetCancelsActiveRecordingAndReturnsToIdle() async {
        let speechService = ControllableSpeechService()
        await speechService.setStartBehavior(.suspended)
        let session = DictationSession(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        session.startCapture()
        session.cancel()
        await Task.yield()

        #expect(session.state == .idle)
        #expect(await speechService.counts().cancel == 1)
    }

    @Test func resetDuringProcessingDiscardsLateTranscriptionResult() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(.suspended)
        await speechService.setCancelFailsPendingStop(false)
        let session = DictationSession(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        session.startCapture()
        #expect(await TestSupport.eventually { session.state == .listening })

        session.stopCapture()
        #expect(await TestSupport.eventually { session.state == .processing })
        #expect(await TestSupport.eventuallyAsync { await speechService.counts().stop == 1 })

        session.cancel()
        #expect(session.state == .idle)
        #expect(await TestSupport.eventuallyAsync { await speechService.counts().cancel == 1 })

        await speechService.finishStop(with: "should not be delivered")
        try await Task.sleep(for: .milliseconds(50))

        #expect(session.state == .idle)
    }

    @Test func explicitActivationKeepsViewModelStartingUntilActivated() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setActivationBehavior(.suspended)
        let session = DictationSession(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        session.startCapture(activateWhenReady: false)
        #expect(await TestSupport.eventuallyAsync { await speechService.counts().start == 1 })
        #expect(session.state == .starting)

        session.activateCaptureWindow()
        #expect(await TestSupport.eventuallyAsync { await speechService.counts().activate == 1 })
        #expect(session.state == .starting)

        await speechService.allowActivation()
        #expect(await TestSupport.eventually { session.state == .listening })
    }

    @Test func pendingActivationDuringStartupActivatesOnceStartCompletes() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStartBehavior(.suspended)
        await speechService.setActivationBehavior(.suspended)
        let session = DictationSession(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        session.startCapture(activateWhenReady: false)
        session.activateCaptureWindow()

        #expect(session.state == .starting)
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

        #expect(await TestSupport.eventually(timeout: .seconds(5)) { session.state == .listening })
        #expect(await speechService.counts().start == 1)
        #expect(await speechService.counts().activate == 1)
    }

    @Test func manualActivationFallbackActivatesCaptureIfControllerNeverSignals() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setActivationBehavior(.suspended)
        let session = DictationSession(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        session.startCapture(activateWhenReady: false)

        #expect(session.state == .starting)
        #expect(
            await TestSupport.eventuallyAsync(timeout: .seconds(8)) {
                await speechService.counts().activate == 1
            })
        await speechService.allowActivation()

        #expect(await TestSupport.eventually(timeout: .seconds(8)) { session.state == .listening })
        #expect(await speechService.counts().start == 1)
        #expect(await speechService.counts().activate == 1)
    }

    @Test func manualActivationFallbackFailureClearsPreparedCaptureAndMetering() async throws {
        let speech = ControllableSpeechService()
        await speech.setActivationBehavior(.fail(SpeechServiceError.failedToStart))
        let session = DictationSession(
            speechService: speech,
            manualActivationFallbackDelay: .milliseconds(1)
        )
        session.startCapture(activateWhenReady: false)
        try #require(await TestSupport.eventuallyAsync { await speech.counts().activate == 1 })
        #expect(
            await TestSupport.eventually {
                session.state == .error(.from(SpeechServiceError.failedToStart))
            })
        #expect(session.recordingLevel == 0)
        await speech.emitLevel(0.9)
        try await Task.sleep(for: .milliseconds(30))
        #expect(session.recordingLevel == 0)
        session.activateCaptureWindow()
        try await Task.sleep(for: .milliseconds(30))
        #expect(await speech.counts().activate == 1)
    }

    @Test func startFailurePublishesStructuredFailure() async {
        let speechService = ControllableSpeechService()
        await speechService.setStartBehavior(.fail(SpeechServiceError.microphonePermissionDenied))
        let session = DictationSession(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        session.startCapture()

        #expect(
            await TestSupport.eventually {
                session.state == .error(.microphonePermissionDenied)
            })
    }

    @Test func stopFailurePreservesStructuredProviderFailure() async {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(.fail(OpenAIError.missingAPIKey(provider: .groq)))
        let session = DictationSession(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        session.startCapture()
        #expect(await TestSupport.eventually { session.state == .listening })

        session.stopCapture()

        #expect(
            await TestSupport.eventually {
                session.state == .error(.missingAPIKey(provider: .groq))
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
        let session = DictationSession(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        session.startCapture()
        #expect(await TestSupport.eventually { session.state == .listening })

        session.stopCapture()

        #expect(
            await TestSupport.eventually {
                session.state
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
        let session = DictationSession(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        session.startCapture()
        #expect(await TestSupport.eventually { session.state == .listening })

        session.stopCapture()

        #expect(
            await TestSupport.eventually {
                session.state
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
        let session = DictationSession(
            speechService: speechService,
            manualActivationFallbackDelay: fallbackDelay
        )

        session.startCapture()
        #expect(await TestSupport.eventually { session.state == .listening })

        session.stopCapture()

        #expect(await TestSupport.eventually { session.state == .idle })
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

    func recordRawWithoutHotwords(_ text: String) {}

    func commitPending() -> UUID? {
        commitCount += 1
        return UUID()
    }
}
