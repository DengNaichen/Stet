#if os(macOS)
    import AppKit

    struct MacDictationPanelLayout {
        let panelSize: CGSize
        let bottomInset: CGFloat
        let scale: CGFloat

        static let fixed = MacDictationPanelLayout(
            panelSize: CGSize(width: 1480, height: 424),
            bottomInset: 12,
            scale: 0.66
        )
    }
#endif
