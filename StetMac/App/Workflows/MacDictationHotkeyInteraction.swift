struct MacDictationHotkeyInteraction {
    enum Action: Equatable {
        case none
        case startCapture
        case stopCapture
    }

    func handleKeyDown(for dictationState: DictationState) -> Action {
        switch dictationState {
        case .starting, .listening:
            .stopCapture
        case .idle, .result, .error:
            .startCapture
        case .clipboardPending, .processing:
            .none
        }
    }
}
