#if os(macOS)
import AppKit

struct MacDictationPanelLayout {
    let collapsedPanelWidth: CGFloat
    let expandedPanelWidth: CGFloat
    let collapsedPanelHeight: CGFloat
    let expandedPanelHeight: CGFloat
    let bottomInset: CGFloat
    let scale: CGFloat

    func panelSize(for state: DictationState) -> CGSize {
        CGSize(
            width: isExpanded(state) ? expandedPanelWidth : collapsedPanelWidth,
            height: isExpanded(state) ? expandedPanelHeight : collapsedPanelHeight
        )
    }

    private func isExpanded(_ state: DictationState) -> Bool {
        if case .clipboardPending = state {
            return true
        }

        return false
    }

    static let standard = MacDictationPanelLayout(
        collapsedPanelWidth: 520,
        expandedPanelWidth: 520,
        collapsedPanelHeight: 92,
        expandedPanelHeight: 140,
        bottomInset: 18,
        scale: 1
    )

    static let compact = MacDictationPanelLayout(
        collapsedPanelWidth: 484,
        expandedPanelWidth: 484,
        collapsedPanelHeight: 86,
        expandedPanelHeight: 129,
        bottomInset: 14,
        scale: 0.92
    )

    static func `for`(screen: NSScreen?) -> MacDictationPanelLayout {
        guard let visibleFrame = screen?.visibleFrame else {
            return .standard
        }

        if visibleFrame.width < 1400 || visibleFrame.height < 900 {
            return .compact
        }

        return .standard
    }
}
#endif
