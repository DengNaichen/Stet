#if os(macOS)
    import Foundation
    import StetVisuals

    protocol AudioFeatureSource: Sendable {
        func makeAudioFeatureStream() async -> AsyncStream<MacDictationCapsuleVisualSignals>
    }

    nonisolated final class AudioFeatureBridge: @unchecked Sendable {
        private let lock = NSLock()
        private var continuations: [UUID: AsyncStream<MacDictationCapsuleVisualSignals>.Continuation] = [:]

        nonisolated init() {}

        nonisolated func makeStream() -> AsyncStream<MacDictationCapsuleVisualSignals> {
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

        nonisolated func emit(_ signals: MacDictationCapsuleVisualSignals) {
            let currentContinuations = withContinuations { Array($0.values) }
            for continuation in currentContinuations {
                continuation.yield(signals)
            }
        }

        nonisolated private func removeContinuation(for identifier: UUID) {
            lock.lock()
            continuations.removeValue(forKey: identifier)
            lock.unlock()
        }

        nonisolated private func withContinuations<T>(
            _ operation: (inout [UUID: AsyncStream<MacDictationCapsuleVisualSignals>.Continuation]) -> T
        ) -> T {
            lock.lock()
            defer { lock.unlock() }
            return operation(&continuations)
        }
    }
#endif
