import Testing

@testable import airType

@Suite("Mac Dictation Hotkey Interaction", .serialized)
struct MacDictationHotkeyInteractionTests {
    @Test func shortPressLatchesListeningAndSecondPressStops() {
        var interaction = MacDictationHotkeyInteraction()

        #expect(interaction.handleKeyDown(for: .idle, now: 10) == .startCapture)
        #expect(interaction.state == .pressCandidate(startedAt: 10))

        #expect(interaction.handleKeyUp(for: .listening, now: 10.1) == .none)
        #expect(interaction.state == .latchedListening)

        #expect(interaction.handleKeyDown(for: .listening, now: 10.2) == .stopCapture)
        #expect(interaction.state == .suppressNextKeyUp)

        #expect(interaction.handleKeyUp(for: .processing, now: 10.21) == .none)
        #expect(interaction.state == .idle)
    }

    @Test func heldPressStopsOnRelease() {
        var interaction = MacDictationHotkeyInteraction()

        #expect(interaction.handleKeyDown(for: .idle, now: 20) == .startCapture)
        #expect(interaction.handleKeyUp(for: .listening, now: 20.35) == .stopCapture)
        #expect(interaction.state == .idle)
    }

    @Test func hotkeyCanStopListeningStartedOutsideHotkeyFlow() {
        var interaction = MacDictationHotkeyInteraction()

        #expect(interaction.handleKeyDown(for: .listening, now: 30) == .stopCapture)
        #expect(interaction.state == .suppressNextKeyUp)

        interaction.sync(with: .processing)
        #expect(interaction.state == .idle)
    }

    @Test func processingStateIgnoresHotkeyEvents() {
        var interaction = MacDictationHotkeyInteraction()

        #expect(interaction.handleKeyDown(for: .processing, now: 40) == .none)
        #expect(interaction.handleKeyUp(for: .processing, now: 40.1) == .none)
        #expect(interaction.state == .idle)
    }

    @Test func syncResetsLatchedStateWhenDictationEnds() {
        var interaction = MacDictationHotkeyInteraction()

        _ = interaction.handleKeyDown(for: .idle, now: 50)
        _ = interaction.handleKeyUp(for: .listening, now: 50.1)
        #expect(interaction.state == .latchedListening)

        interaction.sync(with: .result("done"))
        #expect(interaction.state == .idle)
    }
}
