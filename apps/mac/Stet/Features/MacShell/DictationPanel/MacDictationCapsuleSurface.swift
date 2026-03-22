#if os(macOS)
import SwiftUI
import StetVisuals

struct MacDictationCapsuleSurface: View {
    @ObservedObject var viewModel: MacDictationPanelViewModel
    let panelSize: CGSize

    private var visualModel: MacDictationCapsuleVisualModel {
        MacDictationCapsuleVisualModel(
            state: visualState,
            panelSize: panelSize,
            signals: viewModel.visualSignals
        )
    }

    private var visualActions: MacDictationCapsuleVisualActions {
        MacDictationCapsuleVisualActions(
            onDismiss: dismissAction,
            onConfirm: viewModel.performPrimaryAction
        )
    }

    var body: some View {
        MacDictationCapsuleVisualView(
            model: visualModel,
            actions: visualActions
        )
    }

    private var visualState: MacDictationCapsuleVisualState {
        switch viewModel.state {
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
}
#endif
