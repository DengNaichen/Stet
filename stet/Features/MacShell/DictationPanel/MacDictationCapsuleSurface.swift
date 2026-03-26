#if os(macOS)
    import SwiftUI

    struct MacDictationCapsuleSurface: View {
        @ObservedObject var viewModel: MacDictationPanelViewModel
        let panelSize: CGSize
        @AppStorage(MacPreferences.shaderTheme) private var shaderThemeRawValue = MacDictationVisualTheme.egg
            .rawValue

        var body: some View {
            MacDictationCapsuleVisualRenderer(
                state: viewModel.state,
                panelSize: panelSize,
                signals: viewModel.visualSignals,
                theme: shaderTheme,
                onDismiss: dismissAction,
                onConfirm: viewModel.performPrimaryAction
            )
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
