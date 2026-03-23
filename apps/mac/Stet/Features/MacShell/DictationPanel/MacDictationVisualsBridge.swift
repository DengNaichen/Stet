#if os(macOS)
import StetVisuals
import SwiftUI

enum MacDictationVisualsRuntime {
    @MainActor
    static func prewarmIfAvailable() async {
        await MacDictationCapsuleVisualShaderWarmup.prewarmIfAvailable()
    }
}

struct MacDictationCapsuleVisualRenderer: View {
    let state: DictationState
    let panelSize: CGSize
    let signals: MacDictationPanelVisualSignals
    let theme: MacDictationVisualTheme
    let onDismiss: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        MacDictationCapsuleVisualView(
            model: MacDictationCapsuleVisualModel(
                state: visualState,
                panelSize: panelSize,
                signals: visualSignals,
                shaderTheme: shaderTheme
            ),
            actions: MacDictationCapsuleVisualActions(
                onDismiss: onDismiss,
                onConfirm: onConfirm
            )
        )
    }

    private var visualState: MacDictationCapsuleVisualState {
        switch state {
        case .idle, .clipboardPending:
            return .hidden
        case .starting:
            return .starting
        case .listening:
            return .listening
        case .processing:
            return .processing
        case .result:
            return .result
        case .error(let failure):
            return .error(message: failure.message)
        }
    }

    private var visualSignals: MacDictationCapsuleVisualSignals {
        MacDictationCapsuleVisualSignals(
            body: signals.body,
            presence: signals.presence,
            pulse: signals.pulse,
            articulation: signals.articulation
        )
    }

    private var shaderTheme: MacDictationShaderTheme {
        switch theme {
        case .defaultTheme:
            return .defaultTheme
        case .midnight:
            return .midnight
        case .sunset:
            return .sunset
        case .forest:
            return .forest
        }
    }
}
#endif
