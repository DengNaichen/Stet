import Foundation

nonisolated final class AudioCaptureEventBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var epoch: UInt64
    private var nextSample: Int64 = 0
    private var nextSubscriberID: UInt64 = 0
    private var continuations: [UInt64: AsyncStream<AudioCaptureFrame>.Continuation] = [:]

    nonisolated init(initialEpoch: UInt64 = 0) {
        epoch = initialEpoch
    }

    nonisolated func makeStream() -> AsyncStream<AudioCaptureFrame> {
        AsyncStream { continuation in
            let id = lock.withLock { () -> UInt64 in
                nextSubscriberID += 1
                continuations[nextSubscriberID] = continuation
                return nextSubscriberID
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock {
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    nonisolated func emit(samples: [Float]) {
        guard !samples.isEmpty else { return }

        let (frame, continuations) = lock.withLock {
            let normalized = samples.map { min(max($0, -1), 1) }
            let frame = AudioCaptureFrame(
                epoch: epoch,
                startSample: nextSample,
                samples: normalized
            )
            nextSample = frame.endSample
            return (frame, Array(self.continuations.values))
        }
        for continuation in continuations {
            continuation.yield(frame)
        }
    }

    @discardableResult
    nonisolated func beginNextEpoch() -> Int64 {
        lock.withLock {
            epoch += 1
            return nextSample
        }
    }

    nonisolated func currentEpoch() -> UInt64 {
        lock.withLock { epoch }
    }

    nonisolated func currentSamplePosition() -> Int64 {
        lock.withLock { nextSample }
    }

    nonisolated func finish() {
        let continuations = lock.withLock {
            let values = Array(self.continuations.values)
            self.continuations.removeAll()
            return values
        }
        for continuation in continuations {
            continuation.finish()
        }
    }
}
