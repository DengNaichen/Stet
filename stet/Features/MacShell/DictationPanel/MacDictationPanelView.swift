#if os(macOS)
    import SwiftUI

    struct MacDictationPanelView: View {
        @StateObject private var viewModel: MacDictationPanelViewModel

        let layout: MacDictationPanelLayout

        init(layout: MacDictationPanelLayout, appModel: any MacDictationPanelCoordinating) {
            self.layout = layout
            _viewModel = StateObject(wrappedValue: MacDictationPanelViewModel(appModel: appModel))
        }

        var body: some View {
            let panelSize = layout.panelSize

            Group {
                if case .clipboardPending(let text) = viewModel.state {
                    // Scenario B: Specialized Clipboard Display
                    MacDictationClipboardSurface(
                        text: text,
                        layout: layout,
                        onFinish: viewModel.performPrimaryAction
                    )
                } else if case .error(let failure) = viewModel.state {
                    // Scenario C: Specialized Error Display
                    MacDictationErrorSurface(
                        text: failure.surfaceErrorMessage,
                        isInsufficientFunds: failure.isInsufficientFunds,
                        layout: layout,
                        onTopUp: { viewModel.topUp() },
                        onFinish: { viewModel.hidePanel() }
                    )
                } else {
                    // Scenario A: Standard Dictation Capsule
                    MacDictationCapsuleSurface(
                        viewModel: viewModel,
                        panelSize: panelSize
                    )
                }
            }
            .frame(width: panelSize.width, height: panelSize.height)

        }
    }
#endif
