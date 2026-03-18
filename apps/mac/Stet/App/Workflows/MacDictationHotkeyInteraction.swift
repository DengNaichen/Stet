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

    var holdThreshold: TimeInterval = 0.25
    private(set) var state: State = .idle

    mutating func handleKeyDown(
        for dictationState: DictationState,
        now: TimeInterval
    ) -> Action {
        switch dictationState {
        case .listening:
            switch state {
            case .pressCandidate, .suppressNextKeyUp:
                return .none
            case .idle, .latchedListening:
                state = .suppressNextKeyUp
                return .stopCapture
            }
        case .idle, .result, .error:
            guard case .idle = state else { return .none }
            state = .pressCandidate(startedAt: now)
            return .startCapture
        case .clipboardPending:
            return .none
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

            if didHoldPastThreshold, case .listening = dictationState {
                state = .idle
                return .stopCapture
            }

            state = dictationState.isListening ? .latchedListening : .idle
            return .none
        }
    }

    mutating func sync(with dictationState: DictationState) {
        guard !dictationState.isListening else { return }
        state = .idle
    }

    mutating func reset() {
        state = .idle
    }
}

private extension DictationState {
    var isListening: Bool {
        if case .listening = self {
            return true
        }

        return false
    }
}
