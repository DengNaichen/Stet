import Foundation

/// Tracks work that can outlive the microphone session. Access stays on the owning
/// speech-service actor; model cleanup waits for every user of the model context.
nonisolated final class DictationProcessingLifetime {
    private var sessions: Set<UInt64> = []
    private var retiringPrewarms: [Task<Void, Never>] = []
    private var cleanupTask: Task<Void, Never>?
    private var comparisonTask: Task<Void, Never>?
    private var comparisonGeneration: UInt64 = 0
    private let cleanupModels: @Sendable () async -> Void

    init(cleanupModels: @escaping @Sendable () async -> Void) {
        self.cleanupModels = cleanupModels
    }

    func begin(_ sessionID: UInt64) { sessions.insert(sessionID) }
    func finish(_ sessionID: UInt64) { sessions.remove(sessionID) }

    func retirePrewarm(_ task: Task<Void, Never>?) {
        guard let task else { return }
        retiringPrewarms.append(task)
        task.cancel()
    }

    func waitForCleanup(isolation: isolated (any Actor)) async {
        while let cleanupTask { await cleanupTask.value }
    }

    func scheduleCleanupIfIdle(captureIsIdle: Bool, isolation: isolated (any Actor)) {
        guard captureIsIdle, sessions.isEmpty, cleanupTask == nil, comparisonTask == nil else { return }
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
