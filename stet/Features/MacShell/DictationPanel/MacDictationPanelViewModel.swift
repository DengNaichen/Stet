#if os(macOS)
    import Combine
    import Foundation
    import StetVisuals

    @MainActor
    final class MacDictationPanelViewModel: ObservableObject {
        private enum CapsuleScaleTuning {
            static let minimumListeningScale: CGFloat = 0.97
            static let maximumListeningScale: CGFloat = 1.15
            static let easingPower = 0.4
        }

        private let appModel: any MacDictationPanelCoordinating
        private var cancellables = Set<AnyCancellable>()

        @Published private(set) var state: DictationState
        @Published private(set) var statusText: String
        @Published private(set) var recordingLevel: Double
        @Published private(set) var visualSignals: MacDictationPanelVisualSignals
        @Published private(set) var detectedTargetApplication: AppInfo?

        var capsuleScale: CGFloat {
            Self.capsuleScale(for: state, recordingLevel: recordingLevel)
        }

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

        private static func capsuleScale(
            for state: DictationState,
            recordingLevel: Double
        ) -> CGFloat {
            switch state {
            case .starting, .listening:
                let clampedLevel = max(0, min(recordingLevel, 1))
                let easedLevel = pow(clampedLevel, CapsuleScaleTuning.easingPower)
                let scaleRange =
                    CapsuleScaleTuning.maximumListeningScale - CapsuleScaleTuning.minimumListeningScale

                return CapsuleScaleTuning.minimumListeningScale + (CGFloat(easedLevel) * scaleRange)
            case .processing, .idle, .clipboardPending, .result, .error:
                return 1
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
