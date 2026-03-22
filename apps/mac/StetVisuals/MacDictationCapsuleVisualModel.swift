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

public struct MacDictationCapsuleVisualSignals: Equatable {
    public let body: Double
    public let presence: Double
    public let pulse: Double
    public let articulation: Double

    public init(
        body: Double,
        presence: Double,
        pulse: Double,
        articulation: Double
    ) {
        self.body = Self.clamp(body)
        self.presence = Self.clamp(presence)
        self.pulse = Self.clamp(pulse)
        self.articulation = Self.clamp(articulation)
    }

    public static let zero = MacDictationCapsuleVisualSignals(
        body: 0,
        presence: 0,
        pulse: 0,
        articulation: 0
    )

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

public struct MacDictationCapsuleVisualModel: Equatable {
    let state: MacDictationCapsuleVisualState
    let panelSize: CGSize
    let signals: MacDictationCapsuleVisualSignals

    public init(
        state: MacDictationCapsuleVisualState,
        panelSize: CGSize,
        signals: MacDictationCapsuleVisualSignals
    ) {
        self.state = state
        self.panelSize = panelSize
        self.signals = signals
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
            body: 0.1,
            presence: 0.1,
            pulse: 0.05,
            articulation: 0.08,
            detail: 1.0,
            top: .white,
            mid: .white,
            low: .white
        )
        try? await shader.compile(as: .colorEffect)
    }
}
#endif
