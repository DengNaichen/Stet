import Dispatch
import Foundation

/// Tracks work that can outlive the microphone session. Access stays on the owning
/// speech-service actor; model cleanup waits for every user of the model context,
/// keeps models warm across a sliding idle TTL, and evicts immediately on memory pressure.
nonisolated final class DictationProcessingLifetime {
    static let defaultIdleTTL: Duration = .seconds(300)

    private var sessions: Set<UInt64> = []
    private var retiringPrewarms: [Task<Void, Never>] = []
    private var idleTimerTask: Task<Void, Never>?
    private var idleTimerGeneration: UInt64 = 0
    private var cleanupTask: Task<Void, Never>?
    private var comparisonTask: Task<Void, Never>?
    private var comparisonGeneration: UInt64 = 0
    private let idleTTL: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let cleanupModels: @Sendable () async -> Void

    init(
        idleTTL: Duration = .zero,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        cleanupModels: @escaping @Sendable () async -> Void
    ) {
        self.idleTTL = idleTTL
        self.sleep = sleep
        self.cleanupModels = cleanupModels
    }

    func begin(_ sessionID: UInt64) {
        cancelIdleTimer()
        sessions.insert(sessionID)
    }

    func finish(_ sessionID: UInt64) {
        sessions.remove(sessionID)
    }

    func cancelIdleTimer() {
        idleTimerGeneration &+= 1
        idleTimerTask?.cancel()
        idleTimerTask = nil
    }

    func retirePrewarm(_ task: Task<Void, Never>?) {
        guard let task else { return }
        retiringPrewarms.append(task)
        task.cancel()
    }

    func waitForCleanup(isolation: isolated (any Actor)) async {
        cancelIdleTimer()
        let prewarms = retiringPrewarms
        retiringPrewarms.removeAll()
        for task in prewarms { await task.value }
        while let cleanupTask { await cleanupTask.value }
    }

    func scheduleCleanupIfIdle(
        captureIsIdle: Bool,
        isolation: isolated (any Actor),
        recheckCaptureIdle: (() -> Bool)? = nil
    ) {
        guard captureIsIdle, sessions.isEmpty, cleanupTask == nil, comparisonTask == nil else { return }
        if idleTTL <= .zero {
            startImmediateCleanup(isolation: isolation)
            return
        }

        cancelIdleTimer()
        idleTimerGeneration &+= 1
        let generation = idleTimerGeneration
        let prewarms = retiringPrewarms
        retiringPrewarms.removeAll()
        let ttl = idleTTL
        let sleep = sleep

        idleTimerTask = Task {
            _ = isolation
            for task in prewarms { await task.value }
            guard !Task.isCancelled, idleTimerGeneration == generation else { return }
            do {
                try await sleep(ttl)
            } catch {
                return
            }
            guard !Task.isCancelled, idleTimerGeneration == generation else { return }
            idleTimerTask = nil
            let stillIdle = recheckCaptureIdle?() ?? true
            guard stillIdle, sessions.isEmpty, cleanupTask == nil, comparisonTask == nil else { return }
            startImmediateCleanup(isolation: isolation)
        }
    }

    func evictIdleModelsNow(captureIsIdle: Bool, isolation: isolated (any Actor)) {
        guard captureIsIdle, sessions.isEmpty, cleanupTask == nil, comparisonTask == nil else { return }
        cancelIdleTimer()
        startImmediateCleanup(isolation: isolation)
    }

    private func startImmediateCleanup(isolation: isolated (any Actor)) {
        guard cleanupTask == nil else { return }
        let prewarms = retiringPrewarms
        retiringPrewarms.removeAll()
        cleanupTask = Task {
            _ = isolation
            for task in prewarms { await task.value }
            await cleanupModels()
            cleanupTask = nil
        }
    }

    /// Cancellation does not mean completion: keep the task until its model work has drained.
    func cancelComparison() -> Bool {
        guard let comparisonTask else { return false }
        comparisonTask.cancel()
        return true
    }

    func waitForComparison(isolation: isolated (any Actor)) async {
        await comparisonTask?.value
    }

    /// Takes ownership of the audio file, including on cancellation or transcription failure.
    func startComparison(
        audioURL: URL,
        languageCode: String?,
        duration: TimeInterval?,
        transcriptionService: any AudioFileTranscriptionService,
        record: @escaping @Sendable (String) async -> Void,
        isolation: isolated (any Actor),
        didFinish: @escaping () -> Void
    ) {
        comparisonGeneration += 1
        let generation = comparisonGeneration
        comparisonTask = Task {
            _ = isolation
            defer { try? FileManager.default.removeItem(at: audioURL) }
            if !Task.isCancelled {
                do {
                    let result = try await transcriptionService.transcribe(
                        audioFileAt: audioURL,
                        languageCode: languageCode,
                        prompt: nil,
                        audioDurationSeconds: duration
                    )
                    let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !Task.isCancelled, !text.isEmpty { await record(text) }
                } catch {
                    // The user-facing transcript already succeeded. Skip quietly.
                }
            }
            if comparisonGeneration == generation { comparisonTask = nil }
            didFinish()
        }
    }
}

#if os(macOS)
    nonisolated final class SystemMemoryPressureMonitor: @unchecked Sendable {
        private let lock = NSLock()
        private var source: (any DispatchSourceMemoryPressure)?

        init(onPressure: @escaping @Sendable () -> Void) {
            let source = DispatchSource.makeMemoryPressureSource(
                eventMask: [.warning, .critical],
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler {
                onPressure()
            }
            self.source = source
            source.resume()
        }

        deinit {
            cancel()
        }

        func cancel() {
            lock.lock()
            let current = source
            source = nil
            lock.unlock()
            current?.cancel()
        }
    }
#endif

/// The foreground processing scope owns all intermediate files until it explicitly
/// transfers one to background comparison. Cleanup runs on every exit path.
nonisolated struct DictationAudioFiles {
    private var urls: Set<URL> = []

    mutating func own(_ url: URL) { urls.insert(url) }
    mutating func own(_ urls: [URL]) { self.urls.formUnion(urls) }
    mutating func transfer(_ url: URL) { urls.remove(url) }

    func removeAll() {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }
}
