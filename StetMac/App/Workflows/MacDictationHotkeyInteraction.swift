import Foundation

struct MacDictationHotkeyInteraction {
    enum Action: Equatable {
        case none
        case startCapture
        case stopCapture
    }

    enum State: Equatable {
        case idle
        case pressCandidate(startedAt: TimeInterval)
        case latchedListening
        case suppressNextKeyUp
    }

    var holdThreshold: TimeInterval = 0.35
    private(set) var state: State = .idle

    mutating func handleKeyDown(
        for dictationState: DictationState,
        now: TimeInterval
    ) -> Action {
        switch dictationState {
        case .starting, .listening:
            switch state {
            case .pressCandidate, .suppressNextKeyUp:
                return .none
            case .idle, .latchedListening:
                state = .suppressNextKeyUp
                return .stopCapture
            }
        case .idle, .result, .error, .clipboardPending:
            guard case .idle = state else { return .none }
            state = .pressCandidate(startedAt: now)
            return .startCapture
        case .processing:
            return .none
        }
    }

    mutating func handleKeyUp(
        for dictationState: DictationState,
        now: TimeInterval
    ) -> Action {
        switch state {
        case .idle, .latchedListening:
            return .none
        case .suppressNextKeyUp:
            state = .idle
            return .none
        case .pressCandidate(let startedAt):
            let didHoldPastThreshold = (now - startedAt) >= holdThreshold

            if didHoldPastThreshold, dictationState.isCaptureInFlight {
                state = .idle
                return .stopCapture
            }

            state = dictationState.isCaptureInFlight ? .latchedListening : .idle
            return .none
        }
    }

    mutating func sync(with dictationState: DictationState) {
        guard !dictationState.isCaptureInFlight else { return }
        state = .idle
    }

    mutating func reset() {
        state = .idle
    }
}
