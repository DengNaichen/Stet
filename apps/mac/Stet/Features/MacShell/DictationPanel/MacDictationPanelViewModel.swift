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
        static let silenceFloor: Double = 0.035
        static let publishEpsilon: Double = 0.0005
        static let snapToZeroThreshold: Double = 0.0015
    }

    enum Smoothing {
        static let minDeltaTime: TimeInterval = 1.0 / 240.0
        static let maxDeltaTime: TimeInterval = 0.25
        static let minTimeConstant: TimeInterval = 0.001
    }

    enum Normalization {
        static let levelPower: Double = 1.10
        static let divisorEpsilon: Double = 0.0001
    }
}

@MainActor
final class MacDictationPanelViewModel: ObservableObject {
    private let appModel: any MacDictationPanelCoordinating
    private var cancellables = Set<AnyCancellable>()
    private var targetRecordingLevel: Double
    private var lastSmoothingTimestamp: TimeInterval

    @Published private(set) var state: DictationState
    @Published private(set) var statusText: String
    @Published private(set) var recordingLevel: Double

    init(appModel: any MacDictationPanelCoordinating) {
        self.appModel = appModel
        self.state = appModel.dictationState
        self.statusText = appModel.statusText

        let initialTarget = Self.normalizedRecordingLevel(
            raw: appModel.recordingLevel,
            state: appModel.dictationState
        )

        self.targetRecordingLevel = initialTarget
        self.recordingLevel = initialTarget
        self.lastSmoothingTimestamp = Date().timeIntervalSinceReferenceDate

        appModel.updates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncFromAppModel()
            }
            .store(in: &cancellables)

        Timer.publish(every: Constants.Tuning.smoothingFrameInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.advanceRecordingLevel(to: date.timeIntervalSinceReferenceDate)
            }
            .store(in: &cancellables)
    }

    private func syncFromAppModel() {
        state = appModel.dictationState
        statusText = appModel.statusText
        targetRecordingLevel = Self.normalizedRecordingLevel(
            raw: appModel.recordingLevel,
            state: appModel.dictationState
        )
    }

    private func advanceRecordingLevel(to timestamp: TimeInterval) {
        let deltaTime = min(max(timestamp - lastSmoothingTimestamp, Constants.Smoothing.minDeltaTime), Constants.Smoothing.maxDeltaTime)
        lastSmoothingTimestamp = timestamp

        let current = recordingLevel
        let target = targetRecordingLevel

        let timeConstant: TimeInterval
        if target > current {
            timeConstant = Constants.Tuning.attackTime
        } else if Self.isVoiceReactiveState(state) {
            timeConstant = Constants.Tuning.releaseTime
        } else {
            timeConstant = Constants.Tuning.decayTime
        }

        let alpha = 1.0 - exp(-deltaTime / max(timeConstant, Constants.Smoothing.minTimeConstant))
        var next = current + (target - current) * alpha

        if target == 0, next < Constants.Tuning.snapToZeroThreshold {
            next = 0
        }

        if abs(next - current) > Constants.Tuning.publishEpsilon {
            recordingLevel = next
        }
    }

    private static func normalizedRecordingLevel(raw: Double, state: DictationState) -> Double {
        guard isVoiceReactiveState(state) else {
            return 0
        }

        let clamped = min(max(raw, 0), 1)
        let gated = max(0, clamped - Constants.Tuning.silenceFloor) / max(1.0 - Constants.Tuning.silenceFloor, Constants.Normalization.divisorEpsilon)
        return pow(gated, Constants.Normalization.levelPower)
    }

    private static func isVoiceReactiveState(_ state: DictationState) -> Bool {
        switch state {
        case .starting, .listening:
            return true
        default:
            return false
        }
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
