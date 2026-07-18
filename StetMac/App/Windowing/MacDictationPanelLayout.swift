#if os(macOS)
    import AppKit

    struct MacDictationPanelLayout {
        let panelSize: CGSize
        let bottomInset: CGFloat
        let scale: CGFloat

        static let fixed = MacDictationPanelLayout(
            panelSize: CGSize(width: 370, height: 106),
            bottomInset: 12,
            scale: 0.66
        )
    }
#endif
