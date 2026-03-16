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
        panelSize: CGSize(width: 328, height: 84),
        capsuleSize: CGSize(width: 304, height: 56),
        bottomInset: 52,
        horizontalPadding: 12,
        verticalPadding: 8,
        controlButtonSize: 40,
        controlSymbolSize: 18,
        statusFontSize: 13,
        secondaryFontSize: 11,
        voiceBarHeight: 26
    )

    static let compact = MacDictationPanelLayout(
        panelSize: CGSize(width: 312, height: 80),
        capsuleSize: CGSize(width: 288, height: 52),
        bottomInset: 44,
        horizontalPadding: 10,
        verticalPadding: 7,
        controlButtonSize: 38,
        controlSymbolSize: 17,
        statusFontSize: 12,
        secondaryFontSize: 10,
        voiceBarHeight: 24
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
