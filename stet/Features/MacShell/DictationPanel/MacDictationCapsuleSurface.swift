#if os(macOS)
    import SwiftUI

    struct MacDictationCapsuleSurface: View {
        private static let breathingAnimation = Animation.spring(response: 0.18, dampingFraction: 0.82)
        private static let breathingFadeOut = Animation.easeOut(duration: 0.4)

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
            .scaleEffect(viewModel.breathingScale)
            .animation(Self.breathingFadeOut, value: viewModel.breathingScale)
            .scaleEffect(viewModel.capsuleScale)
            .animation(Self.breathingAnimation, value: viewModel.capsuleScale)
        }

        private func dismissAction() {
            switch viewModel.state {
            case .listening, .starting:
                viewModel.cancelActiveCapture()
            case .idle, .error(_):
                viewModel.hidePanel()
            default:
                break
            }
        }

        private var shaderTheme: MacDictationVisualTheme {
            MacDictationVisualTheme.fromStoredValue(shaderThemeRawValue)
        }
    }
#endif
