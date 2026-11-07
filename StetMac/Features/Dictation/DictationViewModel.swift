import Foundation
import Combine
#if os(macOS)
    import StetCore
    import StetVisuals
#endif

/// Adapts session output for views and owns feedback after text delivery.
@MainActor
final class DictationViewModel: ObservableObject {
    typealias ResultTransformer = DictationSession.ResultTransformer

    @Published private(set) var state: DictationState
    let metering = DictationMeteringState()

    private let session: DictationSession
    private var cancellables = Set<AnyCancellable>()

    var captureSessionID: UInt64 { session.captureSessionID }
    var recordingLevel: Double { metering.recordingLevel }
    #if os(macOS)
        var audioFeatures: MacDictationCapsuleVisualSignals { metering.audioFeatures }
    #endif

    init(session: DictationSession) {
        self.session = session
        state = session.state
        session.$state
            .sink { [weak self] in self?.state = $0 }
            .store(in: &cancellables)
        session.$hasPreparedCapture.dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        session.$recordingLevel
            .sink { [weak self] in self?.metering.recordingLevel = $0 }
            .store(in: &cancellables)
        #if os(macOS)
            session.$audioFeatures
                .sink { [weak self] in self?.metering.audioFeatures = $0 }
                .store(in: &cancellables)
        #endif
    }

    func send(_ action: DictationAction) {
        DictationRuntimeProbe.shared.markAction("dictationAction.\(actionName(for: action))")
        switch action {
        case .startTapped:
            guard case .idle = state else { return }
            startCapture()
        case .stopTapped:
            guard state.isCaptureInFlight else { return }
            stopCapture()
        case .resetTapped:
            session.cancel()
        case .transcriptionSucceeded(let text):
            state = .result(text)
        case .clipboardPending(let text):
            state = .clipboardPending(text)
        case .transcriptionFailed(let failure):
            state = .error(failure)
        }
    }

    func prewarm() async {
        await session.prewarm()
    }

    func startCapture(transform: ResultTransformer? = nil) {
        session.startCapture(transform: transform)
    }

    func startCapture(activateWhenReady: Bool, transform: ResultTransformer? = nil) {
        session.startCapture(activateWhenReady: activateWhenReady, transform: transform)
    }

    func activateCaptureWindow() {
        session.activateCaptureWindow()
    }

    func stopCapture(onCaptureStopped: (@MainActor @Sendable () -> Void)? = nil) {
        session.stopCapture(onCaptureStopped: onCaptureStopped)
    }

    private func actionName(for action: DictationAction) -> String {
        switch action {
        case .startTapped:
            return "startTapped"
        case .stopTapped:
            return "stopTapped"
        case .resetTapped:
            return "resetTapped"
        case .transcriptionSucceeded:
            return "transcriptionSucceeded"
        case .clipboardPending:
            return "clipboardPending"
        case .transcriptionFailed:
            return "transcriptionFailed"
        }
    }
}
