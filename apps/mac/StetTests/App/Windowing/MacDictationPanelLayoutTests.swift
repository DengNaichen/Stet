#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Mac Dictation Panel Layout", .serialized)
struct MacDictationPanelLayoutTests {
    @Test func panelSizeUsesExpandedHeightOnlyForClipboardPendingState() {
        let standard = MacDictationPanelLayout.standard

        let nonClipboardStates: [DictationState] = [
            .idle,
            .listening,
            .processing,
            .result("result"),
            .error("error")
        ]

        for state in nonClipboardStates {
            let size = standard.panelSize(for: state)
            #expect(size.width == standard.panelWidth)
            #expect(size.height == standard.collapsedPanelHeight)
        }

        let clipboardSize = standard.panelSize(for: .clipboardPending("copied text"))
        #expect(clipboardSize.width == standard.panelWidth)
        #expect(clipboardSize.height == standard.expandedPanelHeight)
    }

    @Test func panelLayoutForNilScreenReturnsStandard() {
        let layout = MacDictationPanelLayout.for(screen: nil)
        #expect(layout.panelWidth == MacDictationPanelLayout.standard.panelWidth)
        #expect(layout.collapsedPanelHeight == MacDictationPanelLayout.standard.collapsedPanelHeight)
        #expect(layout.expandedPanelHeight == MacDictationPanelLayout.standard.expandedPanelHeight)
        #expect(layout.bottomInset == MacDictationPanelLayout.standard.bottomInset)
        #expect(layout.scale == MacDictationPanelLayout.standard.scale)
    }

    @Test func panelLayoutForScreenRespectsCompactOrStandardThresholds() {
        guard let screen = NSScreen.main else {
            return
        }

        let layout = MacDictationPanelLayout.for(screen: screen)
        let expected: MacDictationPanelLayout = {
            let visibleFrame = screen.visibleFrame
            if visibleFrame.width < 1400 || visibleFrame.height < 900 {
                return .compact
            }
            return .standard
        }()

        #expect(layout.panelWidth == expected.panelWidth)
        #expect(layout.collapsedPanelHeight == expected.collapsedPanelHeight)
        #expect(layout.expandedPanelHeight == expected.expandedPanelHeight)
        #expect(layout.bottomInset == expected.bottomInset)
        #expect(layout.scale == expected.scale)
    }
}
#endif
