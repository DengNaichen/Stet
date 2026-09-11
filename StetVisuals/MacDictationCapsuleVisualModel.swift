#if os(macOS)
    import Metal
    import SwiftUI

    public enum MacDictationCapsuleVisualState: Equatable {
        case hidden
        case starting
        case listening
        case processing
        case result
        case error(message: String)
    }

    public struct MacDictationCapsuleVisualModel: Equatable {
        let state: MacDictationCapsuleVisualState
        let panelSize: CGSize
        let signals: MacDictationCapsuleVisualSignals
        let shaderTheme: MacDictationShaderTheme

        public init(
            state: MacDictationCapsuleVisualState,
            panelSize: CGSize,
            signals: MacDictationCapsuleVisualSignals,
            shaderTheme: MacDictationShaderTheme
        ) {
            self.state = state
            self.panelSize = panelSize
            self.signals = signals
            self.shaderTheme = shaderTheme
        }

    }

    public struct MacDictationCapsuleVisualActions {
        let onDismiss: () -> Void
        let onConfirm: () -> Void

        public init(
            onDismiss: @escaping () -> Void,
            onConfirm: @escaping () -> Void
        ) {
            self.onDismiss = onDismiss
            self.onConfirm = onConfirm
        }
    }

    public enum MacDictationCapsuleVisualShaderWarmup {
        @MainActor
        public static func prewarmIfAvailable() async {
            _ = MTLCreateSystemDefaultDevice()
        }
    }
#endif
