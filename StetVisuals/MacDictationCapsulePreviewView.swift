#if os(macOS)
    import SwiftUI

    /// A lightweight capsule preview that renders the shader without glass effects.
    /// Suitable for embedding in standard windows (e.g. onboarding).
    public struct MacDictationCapsulePreviewView: View {
        let theme: MacDictationShaderTheme
        let scale: CGFloat

        public init(theme: MacDictationShaderTheme, scale: CGFloat = 1) {
            self.theme = theme
            self.scale = scale
        }

        private var baseWidth: CGFloat { MacDictationPanelConstants.Layout.mainWidthListening }
        private var baseHeight: CGFloat { MacDictationPanelConstants.Layout.controlHeight }

        public var body: some View {
            MacDictationShaderLayer(
                state: .listening,
                mainWidth: baseWidth,
                controlHeight: baseHeight,
                startDate: .now,
                shaderFrameInterval: MacDictationPanelConstants.VoiceReactivity.shaderFrameIntervalActive,
                signals: .zero,
                shaderTheme: theme,
                isPaused: false
            )
            .frame(width: baseWidth, height: baseHeight)
            .scaleEffect(scale)
            .frame(width: baseWidth * scale, height: baseHeight * scale)
        }
    }
#endif
