#if os(macOS)
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
    let displayLevel: Double

    public init(
        state: MacDictationCapsuleVisualState,
        panelSize: CGSize,
        normalizedRecordingLevel: Double
    ) {
        self.state = state
        self.panelSize = panelSize
        self.displayLevel = Self.makeDisplayLevel(
            state: state,
            normalizedRecordingLevel: normalizedRecordingLevel
        )
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
        case .starting, .listening, .processing:
            return false
        case .hidden, .result, .error:
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
        case .starting, .listening:
            return true
        case .hidden, .processing, .result, .error:
            return false
        }
    }

    var overlayMessage: String? {
        guard case .error(let message) = state else {
            return nil
        }

        return message
    }

    private static func makeDisplayLevel(
        state: MacDictationCapsuleVisualState,
        normalizedRecordingLevel: Double
    ) -> Double {
        let easedLevel = pow(
            min(max(normalizedRecordingLevel, 0), 1),
            MacDictationPanelConstants.VoiceReactivity.easedPower
        )

        switch state {
        case .hidden:
            return MacDictationPanelConstants.VoiceReactivity.levelBaseIdle
        case .starting:
            let reactiveLevel = min(
                1,
                MacDictationPanelConstants.VoiceReactivity.shaderDriveFloorStarting +
                    pow(easedLevel, MacDictationPanelConstants.VoiceReactivity.shaderDrivePower) *
                    MacDictationPanelConstants.VoiceReactivity.shaderDriveBoostStarting
            )
            return min(
                MacDictationPanelConstants.VoiceReactivity.levelMaxStarting,
                MacDictationPanelConstants.VoiceReactivity.levelBaseStarting +
                    reactiveLevel * MacDictationPanelConstants.VoiceReactivity.levelMultStarting
            )
        case .listening:
            let reactiveLevel = min(
                1,
                MacDictationPanelConstants.VoiceReactivity.shaderDriveFloorListening +
                    pow(easedLevel, MacDictationPanelConstants.VoiceReactivity.shaderDrivePower) *
                    MacDictationPanelConstants.VoiceReactivity.shaderDriveBoostListening
            )
            return min(
                MacDictationPanelConstants.VoiceReactivity.levelMaxListening,
                MacDictationPanelConstants.VoiceReactivity.levelBaseListening +
                    reactiveLevel * MacDictationPanelConstants.VoiceReactivity.levelMultListening
            )
        case .processing:
            return MacDictationPanelConstants.VoiceReactivity.levelBaseProcessing
        case .result:
            return MacDictationPanelConstants.VoiceReactivity.levelBaseResult
        case .error:
            return 0
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
        guard #available(macOS 15.0, *) else {
            return
        }

        let shader = StetVisualsShaderLibrary.cloudOrbGlassWide(
            size: CGSize(width: 250, height: 52),
            time: 0,
            audio: 0.1,
            detail: 1.0,
            top: .white,
            mid: .white,
            low: .white
        )
        try? await shader.compile(as: .colorEffect)
    }
}
#endif
