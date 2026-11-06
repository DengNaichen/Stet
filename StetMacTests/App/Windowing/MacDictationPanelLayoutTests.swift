#if os(macOS)
    import AppKit
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Mac Dictation Panel Layout", .serialized)
    struct MacDictationPanelLayoutTests {
        @Test func fixedLayoutUsesExpectedPanelMetrics() {
            let layout = MacDictationPanelLayout.fixed

            #expect(layout.panelSize == CGSize(width: 370, height: 106))
            #expect(layout.bottomInset == 12)
            #expect(layout.scale == 0.66)
        }
    }
#endif
