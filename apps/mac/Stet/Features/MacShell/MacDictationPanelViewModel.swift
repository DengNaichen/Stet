#if os(macOS)
import Combine
import Foundation

@MainActor
final class MacDictationPanelViewModel: ObservableObject {
    private let appModel: any MacDictationPanelCoordinating
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var state: DictationState
    @Published private(set) var statusText: String
    @Published private(set) var recordingLevel: Double

    init(appModel: any MacDictationPanelCoordinating) {
        self.appModel = appModel
        self.state = appModel.dictationState
        self.statusText = appModel.statusText
        self.recordingLevel = appModel.recordingLevel

        appModel.updates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.syncFromAppModel()
                }
            }
            .store(in: &cancellables)
    }

    private func syncFromAppModel() {
        state = appModel.dictationState
        statusText = appModel.statusText
        recordingLevel = appModel.recordingLevel
    }

    func hidePanel() {
        appModel.hidePanel()
    }

    func dismissPendingCopy() {
        appModel.dismissPendingCopy()
    }

    func cancelActiveCapture() {
        appModel.cancelActiveCapture()
    }

    func performPrimaryAction() {
        appModel.performPrimaryAction()
    }
}
#endif
