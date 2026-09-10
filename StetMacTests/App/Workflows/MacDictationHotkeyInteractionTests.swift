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

    @Test func processingIgnoresHotkeyPress() {
        let interaction = MacDictationHotkeyInteraction()

        #expect(interaction.handleKeyDown(for: .processing) == .none)
    }

    @Test func startActionsRemainAvailableAfterIdleResultErrorAndClipboardPending() {
        let interaction = MacDictationHotkeyInteraction()

        for state in [
            DictationState.idle,
            .result("previous"),
            .error(.failedToStart),
            .clipboardPending("previous"),
        ] {
            #expect(interaction.handleKeyDown(for: state) == .startCapture)
        }
    }

}
