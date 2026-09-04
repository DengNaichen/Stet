import Testing

@testable import Stet

@Suite("Mac Dictation Hotkey Interaction")
struct MacDictationHotkeyInteractionTests {
    @Test func tapStartsCaptureAndSecondTapStops() {
        let interaction = MacDictationHotkeyInteraction()

        #expect(interaction.handleKeyDown(for: .idle) == .startCapture)
        #expect(interaction.handleKeyDown(for: .listening) == .stopCapture)
    }

    @Test func tapStopsListeningStartedOutsideHotkeyFlow() {
        let interaction = MacDictationHotkeyInteraction()

        #expect(interaction.handleKeyDown(for: .listening) == .stopCapture)
        #expect(interaction.handleKeyDown(for: .starting) == .stopCapture)
    }

    @Test func processingAndClipboardPendingIgnoreHotkeyPress() {
        let interaction = MacDictationHotkeyInteraction()

        #expect(interaction.handleKeyDown(for: .processing) == .none)
        #expect(interaction.handleKeyDown(for: .clipboardPending("copied")) == .none)
    }

    @Test func startActionsRemainAvailableAfterIdleResultAndError() {
        let interaction = MacDictationHotkeyInteraction()

        for state in [
            DictationState.idle,
            .result("previous"),
            .error(.failedToStart),
        ] {
            #expect(interaction.handleKeyDown(for: state) == .startCapture)
        }
    }

}
