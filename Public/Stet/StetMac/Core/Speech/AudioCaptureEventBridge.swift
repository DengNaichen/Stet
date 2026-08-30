import Foundation

nonisolated final class AudioCaptureEventBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var epoch: UInt64
    private var nextSample: Int64 = 0
    private var continuation: AsyncStream<AudioCaptureFrame>.Continuation?

    nonisolated init(initialEpoch: UInt64 = 0) {
        epoch = initialEpoch
    }

    nonisolated func makeStream() -> AsyncStream<AudioCaptureFrame> {
        AsyncStream { continuation in
            let previous = lock.withLock {
                let previous = self.continuation
                self.continuation = continuation
                return previous
            }
            previous?.finish()
        }
    }

    nonisolated func emit(samples: [Float]) {
        guard !samples.isEmpty else { return }

        let (frame, continuation) = lock.withLock {
            let normalized = samples.map { min(max($0, -1), 1) }
            let frame = AudioCaptureFrame(
                epoch: epoch,
                startSample: nextSample,
                samples: normalized
            )
            nextSample = frame.endSample
            return (frame, self.continuation)
        }
        continuation?.yield(frame)
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

    nonisolated func finish() {
        let continuation = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.finish()
    }
}
