#if os(macOS)
    import Foundation

    nonisolated struct MacPassiveCaptureLivenessMonitor: Equatable, Sendable {
        static let timeoutSeconds: TimeInterval = 5

        private(set) var startedAt: TimeInterval?
        private(set) var lastFrameAt: TimeInterval?
        private var lastObservedSamplePosition: Int64?

        var hasReceivedFrame: Bool {
            lastFrameAt != nil
        }

        mutating func start(at uptime: TimeInterval, samplePosition: Int64? = nil) {
            startedAt = uptime
            lastFrameAt = nil
            lastObservedSamplePosition = samplePosition
        }

        mutating func recordFrame(at uptime: TimeInterval) {
            guard startedAt != nil else { return }
            lastFrameAt = uptime
        }

        mutating func recordCaptureProgress(through samplePosition: Int64, at uptime: TimeInterval) {
            guard startedAt != nil,
                let lastObservedSamplePosition,
                samplePosition > lastObservedSamplePosition
            else { return }
            self.lastObservedSamplePosition = samplePosition
            lastFrameAt = uptime
        }

        mutating func stop() {
            startedAt = nil
            lastFrameAt = nil
            lastObservedSamplePosition = nil
        }

        func isTimedOut(at uptime: TimeInterval) -> Bool {
            guard let reference = lastFrameAt ?? startedAt else { return false }
            return uptime - reference >= Self.timeoutSeconds
        }
    }
#endif
