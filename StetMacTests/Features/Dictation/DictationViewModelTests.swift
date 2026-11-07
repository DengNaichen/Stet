import Combine
import Testing

@testable import Stet

@MainActor
@Suite("Dictation presentation", .serialized)
struct DictationViewModelTests {
    @Test func sessionTransitionsReachPresentationSynchronously() async throws {
        let speech = ControllableSpeechService()
        await speech.setStopBehavior(.immediate("hello"))
        let session = DictationSession(speechService: speech)
        let model = DictationViewModel(session: session)

        model.send(.startTapped)
        #expect(model.state == .starting)
        #expect(model.captureSessionID == session.captureSessionID)
        try #require(await TestSupport.eventually { model.state == .listening })
        model.send(.stopTapped)
        #expect(model.state == .processing)
        try #require(await TestSupport.eventually { model.state == .result("hello") })
        model.send(.resetTapped)
        #expect(model.state == .idle)
        #expect(model.captureSessionID == session.captureSessionID)
    }

    @Test func meteringDoesNotPublishOrdinaryPresentationChanges() async throws {
        let speech = ControllableSpeechService()
        let model = DictationViewModel(session: DictationSession(speechService: speech))
        model.startCapture()
        try #require(await TestSupport.eventually { model.state == .listening })
        var ordinaryChanges = 0
        var meteringChanges = 0
        let ordinary = model.objectWillChange.sink { ordinaryChanges += 1 }
        let metering = model.metering.objectWillChange.sink { meteringChanges += 1 }

        let received = await TestSupport.eventuallyAsync {
            await speech.emitLevel(0.65)
            return await MainActor.run { model.recordingLevel == 0.65 }
        }

        #expect(received)
        #expect(meteringChanges > 0)
        #expect(ordinaryChanges == 0)
        withExtendedLifetime((ordinary, metering)) {}
        model.send(.resetTapped)
        #expect(model.recordingLevel == 0)
    }

    @Test func deliveryFeedbackIsPresentationOnly() {
        let session = DictationSession(speechService: ControllableSpeechService())
        let model = DictationViewModel(session: session)
        model.send(.clipboardPending("hello"))
        #expect(model.state == .clipboardPending("hello"))
        #expect(session.state == .idle)
        model.send(.transcriptionFailed(.microphonePermissionDenied))
        #expect(model.state == .error(.microphonePermissionDenied))
        model.send(.transcriptionSucceeded("delivered"))
        #expect(model.state == .result("delivered"))
        model.send(.resetTapped)
        #expect(model.state == .idle)
    }
}
