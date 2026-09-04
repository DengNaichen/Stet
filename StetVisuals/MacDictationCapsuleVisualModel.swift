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

        var mainWidth: CGFloat {
            switch state {
            case .hidden:
                MacDictationPanelConstants.Layout.mainWidthIdle
            case .starting:
                MacDictationPanelConstants.Layout.mainWidthStarting
            case .listening:
                MacDictationPanelConstants.Layout.mainWidthListening
            case .processing:
                MacDictationPanelConstants.Layout.mainWidthProcessing
            case .result:
                MacDictationPanelConstants.Layout.mainWidthResult
            case .error:
                MacDictationPanelConstants.Layout.mainWidthError
            }
        }

        var controlHeight: CGFloat {
            MacDictationPanelConstants.Layout.controlHeight
        }

        var shaderFrameInterval: Double {
            MacDictationPanelConstants.VoiceReactivity.shaderFrameIntervalActive
        }

        var isShaderPaused: Bool {
            switch state {
            case .starting, .listening:
                return false
            case .hidden, .processing, .result, .error:
                return true
            }
        }

        var shouldShowPanel: Bool {
            switch state {
            case .starting, .listening, .processing:
                return true
            case .hidden, .result, .error:
                return false
            }
        }

        var shouldShowOrbs: Bool {
            switch state {
            case .starting, .listening, .processing:
                return true
            case .hidden, .result, .error:
                return false
            }
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
