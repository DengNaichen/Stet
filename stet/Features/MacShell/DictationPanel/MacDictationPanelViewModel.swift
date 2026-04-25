#if os(macOS)
    import Combine
    import Foundation
    import StetVisuals

    @MainActor
    final class MacDictationPanelViewModel: ObservableObject {
        private enum CapsuleScaleTuning {
            static let minimumListeningScale: CGFloat = 0.98
            static let maximumListeningScale: CGFloat = 1.08
            static let easingPower = 0.6
            static let breathingAmplitude: CGFloat = 0.025
            static let breathingPeriod: Double = 2.0
        }

        private let appModel: any MacDictationPanelCoordinating
        private var cancellables = Set<AnyCancellable>()
        private var breathingTask: Task<Void, Never>?

        @Published private(set) var state: DictationState
        @Published private(set) var statusText: String
        @Published private(set) var recordingLevel: Double
        @Published private(set) var visualSignals: MacDictationPanelVisualSignals
        @Published private(set) var detectedTargetApplication: AppInfo?
        @Published private(set) var breathingScale: CGFloat = 1.0

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

            updateBreathing(for: state)
        }

        private func syncFromAppModel() {
            let previousState = state
            state = appModel.dictationState
            statusText = appModel.statusText
            recordingLevel = appModel.recordingLevel
            visualSignals = Self.visualSignals(for: appModel.dictationState, appModel: appModel)
            detectedTargetApplication = appModel.detectedTargetApplication

            if state != previousState {
                updateBreathing(for: state)
            }
        }

        private func updateBreathing(for state: DictationState) {
            switch state {
            case .starting, .listening:
                guard breathingTask == nil else { return }
                breathingTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    let fps: Double = 60
                    let increment = (2 * Double.pi) / (CapsuleScaleTuning.breathingPeriod * fps)
                    var phase: Double = 0
                    while !Task.isCancelled {
                        breathingScale = 1.0 + CapsuleScaleTuning.breathingAmplitude * CGFloat(sin(phase))
                        phase += increment
                        try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 / fps))
                    }
                }
            default:
                breathingTask?.cancel()
                breathingTask = nil
                breathingScale = 1.0
            }
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
