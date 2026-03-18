#if os(macOS)
import Combine
import Foundation

@MainActor
final class MacDictationPanelViewModel: ObservableObject {
    private let appModel: MacAppModel
    private var cancellables = Set<AnyCancellable>()

    init(appModel: MacAppModel) {
        self.appModel = appModel

        appModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var state: DictationState {
        appModel.dictationViewModel.state
    }

    var statusText: String {
        appModel.statusText
    }

    var recordingLevel: Double {
        appModel.recordingLevel
    }

    func hidePanel() {
        appModel.hidePanel()
    }

    func cancelActiveCapture() {
        appModel.cancelActiveCapture()
    }

    func performPrimaryAction() {
        appModel.performPrimaryAction()
    }
}
#endif
