import Foundation

// MARK: - Single-Cursor Bounded Audio FIFO

/// Session-owned bounded PCM queue ordered strictly by sample offset.
///
/// Guarantees:
/// 1. Capture appends whole frames under a lightweight lock; `sealEnd()` freezes the
///    terminal offset so late capture callbacks after stop are dropped cleanly.
/// 2. LID reads contiguous prefix snapshots from offset 0 without moving the ASR read cursor.
/// 3. The single ASR consumer pulls chunks sequentially from one shared cursor covering
///    both buffered prefix audio and live streaming frames, preventing burst backpressure.
/// 4. Unconsumed backlog is bounded by `maxUnconsumedSamples`; overflow fails deterministically.
nonisolated final class AudioSessionFIFO: @unchecked Sendable {
    enum FIFOError: LocalizedError, Equatable {
        case backlogExceeded
        case aborted

        var errorDescription: String? {
            switch self {
            case .backlogExceeded:
                "Apple Speech could not keep up with the microphone."
            case .aborted:
                "Audio capture was cancelled."
            }
        }
    }

    struct Snapshot: Sendable {
        let samples: [Float]
        let totalReceivedSamples: Int
        let isSealed: Bool
    }

    private let maxUnconsumedSamples: Int
    private let maxPrefixRetainedSamples: Int
    private let lock = NSLock()

    // Unconsumed audio frames awaiting the ASR consumer.
    private var chunks: [[Float]] = []
    private var headChunkIndex = 0
    private var headSampleOffset = 0
    private var unconsumedSamples = 0

    // Contiguous prefix retained strictly for LID snapshots until LID finishes.
    private var prefixBuffer: [Float] = []
    private var prefixRetentionEnabled = true

    private var totalAppendedSamples = 0
    private var peakUnconsumedSampleCount = 0
    private var isSealed = false
    private var terminalError: (any Error)?

    private var readerContinuation: CheckedContinuation<[Float]?, any Error>?
    private var readerMaxSamples = 0
    private var prefixWaiters: [UUID: (minSamples: Int, continuation: CheckedContinuation<Snapshot, any Error>)] = [:]

    init(
        maxUnconsumedSamples: Int = Int(ASRAudioFrame.sampleRate) * 15,
        maxPrefixRetainedSamples: Int = Int(ASRAudioFrame.sampleRate) * 4
    ) {
        self.maxUnconsumedSamples = maxUnconsumedSamples
        self.maxPrefixRetainedSamples = maxPrefixRetainedSamples
        self.prefixBuffer.reserveCapacity(min(maxPrefixRetainedSamples, Int(ASRAudioFrame.sampleRate) * 2))
    }

    var totalReceivedSamples: Int {
        lock.withLock { totalAppendedSamples }
    }

    var peakUnconsumedSamples: Int {
        lock.withLock { peakUnconsumedSampleCount }
    }

    var hasReceivedFrames: Bool {
        lock.withLock { totalAppendedSamples > 0 }
    }

    /// Appends a captured PCM frame. Safe to invoke directly from the audio capture callback.
    @discardableResult
    func append(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return true }

        var readerToResume: (CheckedContinuation<[Float]?, any Error>, Result<[Float]?, any Error>)?
        var prefixToResume: [(CheckedContinuation<Snapshot, any Error>, Result<Snapshot, any Error>)] = []

        let accepted: Bool = lock.withLock {
            guard !isSealed, terminalError == nil else { return false }

            if unconsumedSamples + samples.count > maxUnconsumedSamples {
                let error = FIFOError.backlogExceeded
                terminalError = error
                chunks.removeAll(keepingCapacity: false)
                headChunkIndex = 0
                headSampleOffset = 0
                unconsumedSamples = 0
                prefixBuffer.removeAll(keepingCapacity: false)
                prefixRetentionEnabled = false
                if let reader = readerContinuation {
                    readerContinuation = nil
                    readerToResume = (reader, .failure(error))
                }
                for (_, waiter) in prefixWaiters {
                    prefixToResume.append((waiter.continuation, .failure(error)))
                }
                prefixWaiters.removeAll()
                return false
            }

            chunks.append(samples)
            unconsumedSamples += samples.count
            totalAppendedSamples += samples.count
            if unconsumedSamples > peakUnconsumedSampleCount {
                peakUnconsumedSampleCount = unconsumedSamples
            }

            if prefixRetentionEnabled, prefixBuffer.count < maxPrefixRetainedSamples {
                let remaining = maxPrefixRetainedSamples - prefixBuffer.count
                if samples.count <= remaining {
                    prefixBuffer.append(contentsOf: samples)
                } else {
                    prefixBuffer.append(contentsOf: samples.prefix(remaining))
                }
            }

            if let reader = readerContinuation, let chunk = dequeueLocked(maxSamples: readerMaxSamples) {
                readerContinuation = nil
                readerToResume = (reader, .success(chunk))
            }

            var readyWaiterIDs: [UUID] = []
            for (id, waiter) in prefixWaiters where totalAppendedSamples >= waiter.minSamples {
                readyWaiterIDs.append(id)
                let snap = Snapshot(
                    samples: prefixBuffer,
                    totalReceivedSamples: totalAppendedSamples,
                    isSealed: isSealed
                )
                prefixToResume.append((waiter.continuation, .success(snap)))
            }
            for id in readyWaiterIDs {
                prefixWaiters.removeValue(forKey: id)
            }

            return true
        }

        if let (continuation, result) = readerToResume {
            continuation.resume(with: result)
        }
        for (continuation, result) in prefixToResume {
            continuation.resume(with: result)
        }
        return accepted
    }

    /// Freezes the end offset on normal stop. All already-appended samples remain drainable;
    /// any late callbacks arriving afterwards are ignored.
    func sealEnd() {
        var readerToResume: (CheckedContinuation<[Float]?, any Error>, Result<[Float]?, any Error>)?
        var prefixToResume: [(CheckedContinuation<Snapshot, any Error>, Result<Snapshot, any Error>)] = []

        lock.withLock {
            guard !isSealed else { return }
            isSealed = true

            if let reader = readerContinuation {
                if let chunk = dequeueLocked(maxSamples: readerMaxSamples) {
                    readerContinuation = nil
                    readerToResume = (reader, .success(chunk))
                } else {
                    readerContinuation = nil
                    readerToResume = (reader, .success(nil))
                }
            }

            let snap = Snapshot(
                samples: prefixBuffer,
                totalReceivedSamples: totalAppendedSamples,
                isSealed: true
            )
            for (_, waiter) in prefixWaiters {
                prefixToResume.append((waiter.continuation, .success(snap)))
            }
            prefixWaiters.removeAll()
        }

        if let (continuation, result) = readerToResume {
            continuation.resume(with: result)
        }
        for (continuation, result) in prefixToResume {
            continuation.resume(with: result)
        }
    }

    /// Aborts the queue immediately on cancellation, failure, or teardown.
    func abort(with error: any Error = CancellationError()) {
        var readerToResume: CheckedContinuation<[Float]?, any Error>?
        var prefixToResume: [CheckedContinuation<Snapshot, any Error>] = []

        lock.withLock {
            guard terminalError == nil else { return }
            terminalError = error
            isSealed = true
            chunks.removeAll(keepingCapacity: false)
            headChunkIndex = 0
            headSampleOffset = 0
            unconsumedSamples = 0
            prefixBuffer.removeAll(keepingCapacity: false)
            prefixRetentionEnabled = false

            readerToResume = readerContinuation
            readerContinuation = nil
            prefixToResume = prefixWaiters.values.map(\.continuation)
            prefixWaiters.removeAll()
        }

        readerToResume?.resume(throwing: error)
        for continuation in prefixToResume {
            continuation.resume(throwing: error)
        }
    }

    /// Releases the LID prefix copy once language routing is locked.
    func releasePrefixRetention() {
        lock.withLock {
            prefixRetentionEnabled = false
            prefixBuffer.removeAll(keepingCapacity: false)
        }
    }

    /// Returns a contiguous snapshot of prefix samples received so far without advancing the ASR cursor.
    func currentPrefixSnapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                samples: prefixBuffer,
                totalReceivedSamples: totalAppendedSamples,
                isSealed: isSealed
            )
        }
    }

    /// Suspends until at least `minSamples` have been received or the FIFO is sealed/aborted.
    func waitForPrefix(minSamples: Int) async throws -> Snapshot {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let immediate: Result<Snapshot, any Error>? = lock.withLock {
                    if let error = terminalError {
                        return .failure(error)
                    }
                    if totalAppendedSamples >= minSamples || isSealed {
                        return .success(
                            Snapshot(
                                samples: prefixBuffer,
                                totalReceivedSamples: totalAppendedSamples,
                                isSealed: isSealed
                            )
                        )
                    }
                    prefixWaiters[waiterID] = (minSamples: minSamples, continuation: continuation)
                    return nil
                }
                if let immediate {
                    continuation.resume(with: immediate)
                }
            }
        } onCancel: {
            let cancelled: CheckedContinuation<Snapshot, any Error>? = lock.withLock {
                prefixWaiters.removeValue(forKey: waiterID)?.continuation
            }
            cancelled?.resume(throwing: CancellationError())
        }
    }

    /// Pulls the next sequential PCM chunk up to `maxSamples`. Returns `nil` once sealed and fully drained.
    func nextChunk(maxSamples: Int = 3_200) async throws -> [Float]? {
        let clampedMax = max(1, maxSamples)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let immediate: Result<[Float]?, any Error>? = lock.withLock {
                    if let error = terminalError {
                        return .failure(error)
                    }
                    if let chunk = dequeueLocked(maxSamples: clampedMax) {
                        return .success(chunk)
                    }
                    if isSealed {
                        return .success(nil)
                    }
                    readerMaxSamples = clampedMax
                    readerContinuation = continuation
                    return nil
                }
                if let immediate {
                    continuation.resume(with: immediate)
                }
            }
        } onCancel: {
            let cancelled: CheckedContinuation<[Float]?, any Error>? = lock.withLock {
                let pending = readerContinuation
                readerContinuation = nil
                return pending
            }
            cancelled?.resume(throwing: CancellationError())
        }
    }

    private func dequeueLocked(maxSamples: Int) -> [Float]? {
        guard unconsumedSamples > 0 else { return nil }

        let targetCount = min(unconsumedSamples, maxSamples)
        var result: [Float] = []
        result.reserveCapacity(targetCount)

        var remaining = targetCount
        while remaining > 0, headChunkIndex < chunks.count {
            let chunk = chunks[headChunkIndex]
            let available = chunk.count - headSampleOffset
            let take = min(remaining, available)
            result.append(contentsOf: chunk[headSampleOffset..<(headSampleOffset + take)])
            headSampleOffset += take
            unconsumedSamples -= take
            remaining -= take
            if headSampleOffset >= chunk.count {
                headChunkIndex += 1
                headSampleOffset = 0
            }
        }

        // Compact consumed chunk references periodically so memory stays bounded.
        if headChunkIndex == chunks.count {
            chunks.removeAll(keepingCapacity: true)
            headChunkIndex = 0
            headSampleOffset = 0
        } else if headChunkIndex >= 32 {
            chunks.removeFirst(headChunkIndex)
            headChunkIndex = 0
        }

        return result
    }
}

// MARK: - Throttled Volume Relay (Keeps File I/O Off Audio Capture Thread)

/// Accepts high-frequency volume updates directly from the audio capture thread with zero I/O,
/// and forwards generation-validated values at a throttled cadence (~25 Hz) to the sink.
nonisolated final class ThrottledVolumeRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var activeGeneration: UUID?
    private var latestLevel: Float = 0
    private var hasPendingValue = false
    private var flushTask: Task<Void, Never>?
    private let interval: Duration
    private let sink: @Sendable (Float) -> Void

    init(
        interval: Duration = .milliseconds(40),
        sink: @escaping @Sendable (Float) -> Void
    ) {
        self.interval = interval
        self.sink = sink
    }

    func beginSession(generation: UUID) {
        let previousTask: Task<Void, Never>? = lock.withLock {
            let old = flushTask
            activeGeneration = generation
            latestLevel = 0
            hasPendingValue = false
            flushTask = Task.detached(priority: .utility) { [weak self] in
                await self?.runFlushLoop(generation: generation)
            }
            return old
        }
        previousTask?.cancel()
    }

    func publish(_ level: Float, generation: UUID) {
        lock.withLock {
            guard activeGeneration == generation else { return }
            latestLevel = level
            hasPendingValue = true
        }
    }

    func endSession(generation: UUID, resetToZero: Bool = true) {
        let taskToCancel: Task<Void, Never>? = lock.withLock {
            guard activeGeneration == generation else { return nil }
            activeGeneration = nil
            hasPendingValue = false
            latestLevel = 0
            let task = flushTask
            flushTask = nil
            return task
        }
        taskToCancel?.cancel()
        if resetToZero, taskToCancel != nil {
            sink(0)
        }
    }

    func stopAll() {
        let taskToCancel: Task<Void, Never>? = lock.withLock {
            activeGeneration = nil
            hasPendingValue = false
            latestLevel = 0
            let task = flushTask
            flushTask = nil
            return task
        }
        taskToCancel?.cancel()
    }

    private func runFlushLoop(generation: UUID) async {
        while !Task.isCancelled {
            let pending: Float? = lock.withLock {
                guard activeGeneration == generation, hasPendingValue else { return nil }
                hasPendingValue = false
                return latestLevel
            }
            if let pending {
                sink(pending)
            }
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
        }
    }
}
