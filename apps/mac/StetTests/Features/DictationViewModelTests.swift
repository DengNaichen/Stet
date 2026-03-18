import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Dictation View Model", .serialized)
struct DictationViewModelTests {
    @Test func startAndStopCaptureProducesResult() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(.immediate("hello world"))
        let viewModel = DictationViewModel(speechService: speechService)

        viewModel.startCapture()
        #expect(viewModel.state == .listening)

        viewModel.stopCapture()
        #expect(await TestSupport.eventually { viewModel.state == .result("hello world") })

        #expect(viewModel.state == .result("hello world"))
        #expect(await speechService.counts().stop == 1)
    }

    @Test func stopWhileStartIsPendingTransitionsThroughProcessing() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStartBehavior(.suspended)
        await speechService.setStopBehavior(.suspended)
        let viewModel = DictationViewModel(speechService: speechService)

        viewModel.startCapture()
        viewModel.stopCapture()
        #expect(viewModel.state == .processing)

        #expect(await TestSupport.eventuallyAsync { await speechService.counts().start == 1 })
        await speechService.allowStart()
        #expect(await TestSupport.eventuallyAsync { await speechService.counts().stop == 1 })
        await speechService.finishStop(with: "completed")
        #expect(await TestSupport.eventually { viewModel.state == .result("completed") })

        #expect(viewModel.state == .result("completed"))
        #expect(await speechService.counts().start == 1)
        #expect(await speechService.counts().stop == 1)
    }

    @Test func transformIsAppliedBeforePublishingResult() async throws {
        let speechService = ControllableSpeechService()
        await speechService.setStopBehavior(.immediate("draft"))
        let viewModel = DictationViewModel(speechService: speechService)

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
        let viewModel = DictationViewModel(speechService: speechService)

        viewModel.startCapture()
        viewModel.send(.resetTapped)
        await Task.yield()

        #expect(viewModel.state == .idle)
        #expect(await speechService.counts().cancel == 1)
    }

    @Test func processingOperationFailurePublishesError() async {
        let speechService = ControllableSpeechService()
        let viewModel = DictationViewModel(speechService: speechService)

        viewModel.runProcessingOperation {
            throw TestError.expected
        }
        await Task.yield()

        #expect(viewModel.state == .error(TestError.expected.localizedDescription))
    }

    @Test func clipboardPendingActionPublishesClipboardPendingState() {
        let speechService = ControllableSpeechService()
        let viewModel = DictationViewModel(speechService: speechService)

        viewModel.send(.clipboardPending("hello"))

        #expect(viewModel.state == .clipboardPending("hello"))
    }
}
