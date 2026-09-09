#if os(macOS)
    import SwiftUI

    struct MacDictationCapsuleSurface: View {
        private static let voiceScaleAnimation = Animation.spring(response: 0.18, dampingFraction: 0.82)

        @ObservedObject var viewModel: MacDictationPanelViewModel
        let panelSize: CGSize
        @AppStorage(MacPreferences.shaderTheme) private var shaderThemeRawValue = MacDictationVisualTheme.egg
            .rawValue

        var body: some View {
            MacDictationCapsuleVisualRenderer(
                state: viewModel.displayState,
                panelSize: panelSize,
                signals: viewModel.visualSignals,
                theme: shaderTheme,
                onDismiss: dismissAction,
                onConfirm: viewModel.performPrimaryAction
            )
            .scaleEffect(viewModel.capsuleScale)
            .animation(Self.voiceScaleAnimation, value: viewModel.capsuleScale)
        }

        private func dismissAction() {
            switch MacDictationCapsuleDismissBehavior.forState(viewModel.state) {
            case .cancelActiveCapture:
                viewModel.cancelActiveCapture()
            case .hidePanel:
                viewModel.hidePanel()
            case .ignore:
                break
            }
        }

        private var shaderTheme: MacDictationVisualTheme {
            MacDictationVisualTheme.fromStoredValue(shaderThemeRawValue)
        }
    }

    enum MacDictationCapsuleDismissBehavior: Equatable {
        case cancelActiveCapture
        case hidePanel
        case ignore

        static func forState(_ state: DictationState) -> Self {
            switch state {
            case .starting, .listening, .processing:
                return .cancelActiveCapture
            case .idle, .error:
                return .hidePanel
            case .result, .clipboardPending:
                return .ignore
            }
        }
    }
#endif
