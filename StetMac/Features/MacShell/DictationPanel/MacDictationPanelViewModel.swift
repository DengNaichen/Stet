#if os(macOS)
    import Combine
    import Foundation
    import StetVisuals

    @MainActor
    final class MacDictationPanelViewModel: ObservableObject {
        private let appModel: any MacDictationPanelCoordinating
        private var cancellables = Set<AnyCancellable>()

        @Published private(set) var state: DictationState
        @Published private(set) var statusText: String
        @Published private(set) var recordingLevel: Double
        @Published private(set) var visualSignals: MacDictationPanelVisualSignals
        @Published private(set) var detectedTargetApplication: AppInfo?

        var displayState: DictationState {
            Self.displayState(for: state, recordingLevel: recordingLevel)
        }

        init(appModel: any MacDictationPanelCoordinating) {
            self.appModel = appModel
            self.state = appModel.dictationState
            self.statusText = appModel.statusText
            self.recordingLevel = appModel.recordingLevel
            self.visualSignals = Self.visualSignals(for: appModel.dictationState, appModel: appModel)
            self.detectedTargetApplication = appModel.detectedTargetApplication

            appModel.updates
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncFromAppModel()
                }
                .store(in: &cancellables)
        }

        private func syncFromAppModel() {
            state = appModel.dictationState
            statusText = appModel.statusText
            recordingLevel = appModel.recordingLevel
            visualSignals = Self.visualSignals(for: appModel.dictationState, appModel: appModel)
            detectedTargetApplication = appModel.detectedTargetApplication
        }

        private static func visualSignals(
            for state: DictationState,
            appModel: any MacDictationPanelCoordinating
        ) -> MacDictationPanelVisualSignals {
            switch state {
            case .starting, .listening:
                return appModel.audioFeatures
            case .processing:
                return appModel.audioFeatures.scaled(by: 0.35)
            case .idle, .clipboardPending, .result, .error:
                return .zero
            }
        }

        private static func displayState(
            for state: DictationState,
            recordingLevel: Double
        ) -> DictationState {
            if case .starting = state,
                recordingLevel > 0
            {
                return .listening
            }

            return state
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
