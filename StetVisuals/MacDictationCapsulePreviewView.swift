#if os(macOS)
    import SwiftUI

    /// Previews the same circular material used by the native dictation panel.
    public struct MacDictationCapsulePreviewView: View {
        let theme: MacDictationShaderTheme
        let scale: CGFloat

        public init(theme: MacDictationShaderTheme, scale: CGFloat = 1) {
            self.theme = theme
            self.scale = scale
        }

        public var body: some View {
            MacWatercolorOrbPreview(theme: theme)
                .frame(width: 64, height: 64)
                .scaleEffect(scale)
                .frame(width: 64 * scale, height: 64 * scale)
        }
    }
#endif
