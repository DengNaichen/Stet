#if os(macOS)
    import Combine
    import Foundation

    // MARK: - Constants

    private enum Constants {
        enum Tuning {
            static let smoothingFrameInterval: TimeInterval = 1.0 / 30.0
            static let attackTime: TimeInterval = 0.080
            static let releaseTime: TimeInterval = 0.320
            static let decayTime: TimeInterval = 0.200
            static let silenceFloor: Double = 0.003
            static let publishEpsilon: Double = 0.0005
            static let snapToZeroThreshold: Double = 0.0015
        }

        enum Smoothing {
            static let minDeltaTime: TimeInterval = 1.0 / 240.0
            static let maxDeltaTime: TimeInterval = 0.25
            static let minTimeConstant: TimeInterval = 0.001
        }

        enum Normalization {
            static let levelPower: Double = 0.54
            static let quietSpeechThreshold: Double = 0.42
            static let quietSpeechBoost: Double = 0.52
            static let divisorEpsilon: Double = 0.0001
        }
    }

    @MainActor
    final class MacDictationPanelViewModel: ObservableObject {
        private let appModel: any MacDictationPanelCoordinating
        private var cancellables = Set<AnyCancellable>()
        private var smoothingCancellable: AnyCancellable?
        private var targetRecordingLevel: Double
        private var lastSmoothingTimestamp: TimeInterval
        private var signalState: MacDictationPanelVisualSignalMapper.State

        @Published private(set) var state: DictationState
        @Published private(set) var statusText: String
        @Published private(set) var recordingLevel: Double
        @Published private(set) var visualSignals: MacDictationPanelVisualSignals
        @Published private(set) var detectedTargetApplication: AppInfo?

        init(appModel: any MacDictationPanelCoordinating) {
            self.appModel = appModel
            self.state = appModel.dictationState
            self.statusText = appModel.statusText
            self.detectedTargetApplication = appModel.detectedTargetApplication

            let initialTarget = Self.normalizedRecordingLevel(
                raw: appModel.recordingLevel,
                state: appModel.dictationState
            )
            let initialSignalState = MacDictationPanelVisualSignalMapper.initialState(
                level: initialTarget,
                isVoiceReactive: Self.isVoiceReactiveState(appModel.dictationState)
            )

            self.targetRecordingLevel = initialTarget
            self.signalState = initialSignalState
            self.recordingLevel = initialSignalState.body
            self.visualSignals = initialSignalState.visualSignals
            self.lastSmoothingTimestamp = Date().timeIntervalSinceReferenceDate

            appModel.updates
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncFromAppModel()
                }
                .store(in: &cancellables)
            updateSmoothingActivity()
        }

        private func syncFromAppModel() {
            state = appModel.dictationState
            statusText = appModel.statusText
            detectedTargetApplication = appModel.detectedTargetApplication
            targetRecordingLevel = Self.normalizedRecordingLevel(
                raw: appModel.recordingLevel,
                state: appModel.dictationState
            )
            updateSmoothingActivity()
        }

        private func advanceRecordingLevel(to timestamp: TimeInterval) {
            let deltaTime = min(
                max(timestamp - lastSmoothingTimestamp, Constants.Smoothing.minDeltaTime),
                Constants.Smoothing.maxDeltaTime)
            lastSmoothingTimestamp = timestamp

            signalState = MacDictationPanelVisualSignalMapper.step(
                state: signalState,
                targetLevel: targetRecordingLevel,
                deltaTime: deltaTime,
                isVoiceReactive: Self.isVoiceReactiveState(state)
            )

            var nextSignals = signalState.visualSignals
            var nextBody = signalState.body

            if targetRecordingLevel == 0, nextBody < Constants.Tuning.snapToZeroThreshold {
                nextBody = 0
                nextSignals = MacDictationPanelVisualSignals(
                    body: 0,
                    presence: nextSignals.presence < Constants.Tuning.snapToZeroThreshold ? 0 : nextSignals.presence,
                    pulse: nextSignals.pulse < Constants.Tuning.snapToZeroThreshold ? 0 : nextSignals.pulse,
                    articulation: nextSignals.articulation < Constants.Tuning.snapToZeroThreshold
                        ? 0 : nextSignals.articulation
                )
            }

            if abs(nextBody - recordingLevel) > Constants.Tuning.publishEpsilon {
                recordingLevel = nextBody
            }

            if shouldPublish(nextSignals, comparedTo: visualSignals) {
                visualSignals = nextSignals
            }

            updateSmoothingActivity()
        }

        private func updateSmoothingActivity() {
            guard shouldKeepSmoothing else {
                smoothingCancellable?.cancel()
                smoothingCancellable = nil
                lastSmoothingTimestamp = Date().timeIntervalSinceReferenceDate
                return
            }

            guard smoothingCancellable == nil else {
                return
            }

            lastSmoothingTimestamp = Date().timeIntervalSinceReferenceDate
            smoothingCancellable = Timer.publish(
                every: Constants.Tuning.smoothingFrameInterval,
                on: .main,
                in: .common
            )
            .autoconnect()
            .sink { [weak self] date in
                self?.advanceRecordingLevel(to: date.timeIntervalSinceReferenceDate)
            }
        }

        private var shouldKeepSmoothing: Bool {
            Self.isVoiceReactiveState(state)
                || targetRecordingLevel > Constants.Tuning.snapToZeroThreshold
                || recordingLevel > Constants.Tuning.snapToZeroThreshold
                || visualSignals.presence > Constants.Tuning.snapToZeroThreshold
                || visualSignals.pulse > Constants.Tuning.snapToZeroThreshold
                || visualSignals.articulation > Constants.Tuning.snapToZeroThreshold
        }

        private static func normalizedRecordingLevel(raw: Double, state: DictationState) -> Double {
            guard isVoiceReactiveState(state) else {
                return 0
            }

            let clamped = min(max(raw, 0), 1)
            let gated =
                max(0, clamped - Constants.Tuning.silenceFloor)
                / max(1.0 - Constants.Tuning.silenceFloor, Constants.Normalization.divisorEpsilon)
            let curved = pow(gated, Constants.Normalization.levelPower)
            let quietBand =
                max(0, Constants.Normalization.quietSpeechThreshold - gated)
                / max(Constants.Normalization.quietSpeechThreshold, Constants.Normalization.divisorEpsilon)
            let quietCompensation = gated * quietBand * Constants.Normalization.quietSpeechBoost
            return min(1, curved + quietCompensation)
        }

        private static func isVoiceReactiveState(_ state: DictationState) -> Bool {
            switch state {
            case .starting, .listening:
                return true
            default:
                return false
            }
        }

        private func shouldPublish(
            _ candidate: MacDictationPanelVisualSignals,
            comparedTo current: MacDictationPanelVisualSignals
        ) -> Bool {
            abs(candidate.body - current.body) > Constants.Tuning.publishEpsilon
                || abs(candidate.presence - current.presence) > Constants.Tuning.publishEpsilon
                || abs(candidate.pulse - current.pulse) > Constants.Tuning.publishEpsilon
                || abs(candidate.articulation - current.articulation) > Constants.Tuning.publishEpsilon
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
