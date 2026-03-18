import Foundation

final class AudioLevelBridge: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var continuations: [UUID: AsyncStream<Double>.Continuation] = [:]

    nonisolated init() {}

    nonisolated func makeStream() -> AsyncStream<Double> {
        let identifier = UUID()

        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            lock.lock()
            continuations[identifier] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(for: identifier)
            }
        }
    }

    nonisolated func emit(_ level: Double) {
        let currentContinuations = withContinuations { Array($0.values) }
        for continuation in currentContinuations {
            continuation.yield(level)
        }
    }

    nonisolated func finish() {
        let currentContinuations = withContinuations { continuations in
            let values = Array(continuations.values)
            continuations.removeAll()
            return values
        }

        for continuation in currentContinuations {
            continuation.finish()
        }
    }

    nonisolated private func removeContinuation(for identifier: UUID) {
        lock.lock()
        continuations.removeValue(forKey: identifier)
        lock.unlock()
    }

    nonisolated private func withContinuations<T>(_ operation: (inout [UUID: AsyncStream<Double>.Continuation]) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation(&continuations)
    }
}
