import Combine
import Foundation
import Testing
@testable import StetMobile

@MainActor
struct AppViewModelTests {
    @Test
    func dictateURLRoutesToCaptureAndCompletionRoutesToReturnGuide() async {
        let coordinator = RoutingDictationCoordinator()
        let dictationViewModel = SenseVoiceViewModel(coordinator: coordinator)
        let subject = AppViewModel(dictationViewModel: dictationViewModel)
        var completions = dictationViewModel.$completedSessionId.values.makeAsyncIterator()
        _ = await completions.next()
        dictationViewModel.start()

        #expect(subject.handleIncomingURL(URL(string: "stetmobile://other")!) == false)
        #expect(subject.selectedTab == .dictionary)
        #expect(subject.externalDictationFlow == .none)

        #expect(subject.handleIncomingURL(URL(string: "stetmobile://dictate")!))
        #expect(subject.selectedTab == .dictation)
        #expect(subject.externalDictationFlow == .capturing)
        #expect(coordinator.synchronizeCallCount == 1)

        coordinator.emit(.completed(sessionId: "session-a", text: "hello", metrics: nil))
        #expect(await completions.next() == "session-a")
        #expect(subject.externalDictationFlow == .returnGuide)

        subject.dismissExternalGuide()
        #expect(subject.externalDictationFlow == .none)
        await coordinator.shutdown()
    }

    @Test
    func rawCoordinatorFailureIsNotExposed() async {
        let coordinator = RoutingDictationCoordinator()
        let liveActivityManager = RecordingMicrophoneLiveActivityManager()
        let subject = SenseVoiceViewModel(
            coordinator: coordinator,
            liveActivityManager: liveActivityManager
        )
        var states = subject.$state.values.makeAsyncIterator()
        var liveActivityCalls = liveActivityManager.calls.makeAsyncIterator()
        _ = await states.next()
        subject.start()

        coordinator.emit(
            .failed(
                sessionId: nil,
                message: "Unsupported ASR model: SenseVoice. HTTP 500."
            )
        )

        #expect(
            await states.next()
                == .failed("Dictation isn't available right now. Please try again.")
        )
        #expect(await liveActivityCalls.next() == .endAll)
        #expect(liveActivityManager.endAllCallCount == 1)
        #expect(subject.partialStatus == "Dictation isn't available right now. Please try again.")
        await coordinator.shutdown()
    }

    @Test
    func readyEnsuresOneLiveActivityWithoutChangingLaterDictationStates() async {
        let coordinator = RoutingDictationCoordinator()
        let liveActivityManager = RecordingMicrophoneLiveActivityManager()
        let subject = SenseVoiceViewModel(
            coordinator: coordinator,
            liveActivityManager: liveActivityManager
        )
        var states = subject.$state.values.makeAsyncIterator()
        var liveActivityCalls = liveActivityManager.calls.makeAsyncIterator()
        _ = await states.next()
        subject.start()

        coordinator.emit(.ready(engineName: "SenseVoice"))
        #expect(await states.next() == .idle)
        #expect(await liveActivityCalls.next() == .ensureActive)
        #expect(liveActivityManager.ensureActiveCallCount == 1)

        coordinator.emit(.ready(engineName: "SenseVoice"))
        #expect(await states.next() == .idle)
        #expect(await liveActivityCalls.next() == .ensureActive)
        #expect(liveActivityManager.ensureActiveCallCount == 2)

        coordinator.emit(.recording(sessionId: "session-a"))
        #expect(await states.next() == .recording)
        #expect(liveActivityManager.ensureActiveCallCount == 2)
        #expect(liveActivityManager.endAllCallCount == 0)

        await coordinator.shutdown()
    }

    @Test
    func handledLiveActivityCreationFailureDoesNotChangeReadyState() async {
        let coordinator = RoutingDictationCoordinator()
        let liveActivityManager = SimulatedCreationFailureLiveActivityManager()
        let subject = SenseVoiceViewModel(
            coordinator: coordinator,
            liveActivityManager: liveActivityManager
        )
        var states = subject.$state.values.makeAsyncIterator()
        _ = await states.next()
        subject.start()

        coordinator.emit(.ready(engineName: "SenseVoice"))

        #expect(await states.next() == .idle)
        #expect(liveActivityManager.ensureActiveCallCount == 1)
        #expect(subject.partialStatus == "Ready. Hold mic on keyboard to dictate.")
        await coordinator.shutdown()
    }

    @Test
    func recordingSamplesScalarVolumeAndProcessingFreezesTheLastLevel() async throws {
        let coordinator = RoutingDictationCoordinator()
        let volumeTransport = MutableVolumeTransport(level: 0.4)
        let subject = SenseVoiceViewModel(
            coordinator: coordinator,
            volumeTransport: volumeTransport
        )
        var states = subject.$state.values.makeAsyncIterator()
        _ = await states.next()
        subject.start()

        coordinator.emit(.recording(sessionId: "session-a"))
        #expect(await states.next() == .recording)
        #expect(isNear(subject.recordingLevel, 0.4))

        volumeTransport.level = 0.9
        try await Task.sleep(for: .milliseconds(80))
        #expect(isNear(subject.recordingLevel, 0.9))

        coordinator.emit(.transcribing(sessionId: "session-a"))
        #expect(await states.next() == .processing)
        let frozenLevel = subject.recordingLevel

        volumeTransport.level = 0.1
        try await Task.sleep(for: .milliseconds(80))
        #expect(subject.recordingLevel == frozenLevel)

        coordinator.emit(.completed(sessionId: "session-a", text: "hello", metrics: nil))
        #expect(await states.next() == .idle)
        #expect(subject.recordingLevel == 0)
        await coordinator.shutdown()
    }

    private func isNear(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.000_001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}

private final class MutableVolumeTransport: DictationVolumeTransporting {
    var level: Float

    init(level: Float) {
        self.level = level
    }

    func updateVolume(_ level: Float) {
        self.level = level
    }

    func readVolume() -> Float {
        level
    }
}

@MainActor
private final class RecordingMicrophoneLiveActivityManager: MicrophoneLiveActivityManaging {
    enum Call: Equatable {
        case ensureActive
        case endAll
    }

    let calls: AsyncStream<Call>
    private(set) var ensureActiveCallCount = 0
    private(set) var endAllCallCount = 0

    private let continuation: AsyncStream<Call>.Continuation

    init() {
        (calls, continuation) = AsyncStream.makeStream()
    }

    func ensureActive() async {
        ensureActiveCallCount += 1
        continuation.yield(.ensureActive)
    }

    func endAll() async {
        endAllCallCount += 1
        continuation.yield(.endAll)
    }
}

@MainActor
private final class SimulatedCreationFailureLiveActivityManager:
    MicrophoneLiveActivityManaging
{
    private(set) var ensureActiveCallCount = 0

    func ensureActive() async {
        ensureActiveCallCount += 1
        // The production manager handles ActivityKit request failures internally.
    }

    func endAll() async {}
}

@MainActor
private final class RoutingDictationCoordinator: DictationSessionCoordinating {
    let events: AsyncStream<DictationCoordinatorEvent>
    private(set) var phase: DictationCoordinatorPhase = .idle

    private let continuation: AsyncStream<DictationCoordinatorEvent>.Continuation
    private(set) var synchronizeCallCount = 0

    init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    func start() {}
    func recoverAudioSession() {}
    func synchronizeKeyboardCommands() {
        synchronizeCallCount += 1
    }
    func startRecording(sessionId _: String) {}
    func stopRecording(sessionId _: String?) {}
    func cancelRecording(sessionId _: String) {}

    func shutdown() async {
        continuation.finish()
    }

    func emit(_ event: DictationCoordinatorEvent) {
        continuation.yield(event)
    }
}
