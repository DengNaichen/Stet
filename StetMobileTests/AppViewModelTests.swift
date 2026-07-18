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
