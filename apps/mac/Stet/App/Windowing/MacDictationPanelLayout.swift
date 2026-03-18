#if os(macOS)
import AppKit

struct MacDictationPanelLayout {
    let panelSize: CGSize
    let capsuleSize: CGSize
    let bottomInset: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let controlButtonSize: CGFloat
    let controlSymbolSize: CGFloat
    let statusFontSize: CGFloat
    let secondaryFontSize: CGFloat
    let voiceBarHeight: CGFloat

    static let standard = MacDictationPanelLayout(
        panelSize: CGSize(width: 304, height: 76),
        capsuleSize: CGSize(width: 280, height: 48),
        bottomInset: 52,
        horizontalPadding: 10,
        verticalPadding: 6,
        controlButtonSize: 34,
        controlSymbolSize: 15,
        statusFontSize: 12,
        secondaryFontSize: 10,
        voiceBarHeight: 20
    )

    static let compact = MacDictationPanelLayout(
        panelSize: CGSize(width: 292, height: 72),
        capsuleSize: CGSize(width: 268, height: 44),
        bottomInset: 44,
        horizontalPadding: 9,
        verticalPadding: 6,
        controlButtonSize: 32,
        controlSymbolSize: 14,
        statusFontSize: 11,
        secondaryFontSize: 10,
        voiceBarHeight: 18
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
