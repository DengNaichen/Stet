import Foundation

/// Owned exclusively by ConfigurableSpeechService. Async operations inherit that actor's
/// isolation so extracting hardware ownership does not add an independently reentrant actor.
nonisolated final class DictationCaptureLifecycle {
    typealias CaptureResult = (url: URL, duration: TimeInterval?)

    private let factory: @Sendable () -> any AudioCaptureService
    private var reusableRecorder: (any AudioCaptureService)?
    private var activeRecorder: (any AudioCaptureService)?
    private var activeSessionID: UInt64?
    private var nextSessionID: UInt64 = 0
    private var invalidatedThroughSessionID: UInt64 = 0
    private var transitionTask: Task<Void, Error>?
    private var stopTask: Task<CaptureResult, Error>?
    private var cancellationTask: Task<Void, Never>?
    private var isProcessing = false

    init(
        recorder: (any AudioCaptureService)?,
        factory: (@Sendable () -> any AudioCaptureService)?
    ) {
        if let recorder {
            reusableRecorder = recorder
            self.factory = { recorder }
        } else if let factory {
            self.factory = factory
        } else {
            let recorder = MacAudioCaptureService()
            reusableRecorder = recorder
            self.factory = { recorder }
        }
    }

    var isIdle: Bool { activeSessionID == nil && cancellationTask == nil }

    func start(
        isolation: isolated (any Actor),
        waitForProcessingCleanup: () async -> Void,
        prepare: @escaping (UInt64) async throws -> Void,
        didCancel: @escaping (UInt64) -> Void
    ) async throws {
        try Task.checkCancellation()
        nextSessionID += 1
        let sessionID = nextSessionID
        // Reserve before waiting: cancellation also invalidates queued starts.
        while let cancellationTask { await cancellationTask.value }
        await waitForProcessingCleanup()
        try Task.checkCancellation()
        guard activeSessionID == nil else { throw SpeechServiceError.alreadyRecording }
        guard sessionID > invalidatedThroughSessionID else { throw CancellationError() }
        activeSessionID = sessionID
        let operation = Task {
            _ = isolation
            try await prepare(sessionID)
        }
        transitionTask = operation
        do {
            try await withTaskCancellationHandler {
                try await operation.value
            } onCancel: {
                operation.cancel()
            }
            try ensureActive(sessionID)
            transitionTask = nil
        } catch {
            if activeSessionID == sessionID, cancellationTask == nil {
                await cancel(isolation: isolation, didCancel: didCancel)
            }
            throw error
        }
    }

    func recorderForSession() -> any AudioCaptureService {
        let recorder = reusableRecorder ?? factory()
        reusableRecorder = recorder
        activeRecorder = recorder
        return recorder
    }

    func activateRecordingWindow(
        isolation: isolated (any Actor),
        didCancel: @escaping (UInt64) -> Void
    ) async throws {
        guard let sessionID = activeSessionID, let activeRecorder, transitionTask == nil else {
            throw SpeechServiceError.notRecording
        }
        try ensureActive(sessionID)
        let operation = Task {
            _ = isolation
            try await activeRecorder.activateRecordingWindow()
        }
        transitionTask = operation
        defer {
            if activeSessionID == sessionID { transitionTask = nil }
        }
        do {
            try await withTaskCancellationHandler {
                try await operation.value
            } onCancel: {
                operation.cancel()
            }
            try ensureActive(sessionID)
        } catch {
            if activeSessionID == sessionID, cancellationTask == nil {
                await cancel(isolation: isolation, didCancel: didCancel)
            }
            throw error
        }
    }

    func beginProcessing() throws -> UInt64 {
        guard let sessionID = activeSessionID, activeRecorder != nil,
            !isProcessing, transitionTask == nil
        else { throw SpeechServiceError.notRecording }
        try ensureActive(sessionID)
        isProcessing = true
        return sessionID
    }

    func stop(
        sessionID: UInt64,
        isolation: isolated (any Actor),
        ownAudio: (URL) -> Void
    ) async throws -> CaptureResult {
        guard let activeRecorder else { throw SpeechServiceError.notRecording }
        let operation = Task {
            _ = isolation
            let result = try await activeRecorder.stopRecording()
            return result
        }
        stopTask = operation
        let result = try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
        // Claim the file even when the stop finished after cancellation.
        ownAudio(result.url)
        try ensureActive(sessionID)
        stopTask = nil
        return result
    }

    func cancel(isolation: isolated (any Actor), didCancel: @escaping (UInt64) -> Void) async {
        invalidatedThroughSessionID = max(invalidatedThroughSessionID, nextSessionID)
        if let cancellationTask {
            await cancellationTask.value
            return
        }
        guard let sessionID = activeSessionID else { return }
        let transition = transitionTask
        let stop = stopTask
        transition?.cancel()
        stop?.cancel()
        let cleanup = Task {
            _ = isolation
            // Drain hardware operations before touching the reusable recorder. ASR may outlive this.
            _ = await transition?.result
            _ = await stop?.result
            if let activeRecorder { await activeRecorder.cancelRecording() }
            cancellationTask = nil
            didCancel(sessionID)
        }
        cancellationTask = cleanup
        await cleanup.value
    }

    /// A late processing completion must never retire a newer recording session.
    @discardableResult
    func finish(_ sessionID: UInt64) -> Bool {
        guard activeSessionID == sessionID else { return false }
        activeSessionID = nil
        activeRecorder = nil
        transitionTask = nil
        stopTask = nil
        isProcessing = false
        return true
    }

    func ensureActive(_ sessionID: UInt64) throws {
        try Task.checkCancellation()
        guard sessionID == activeSessionID, sessionID > invalidatedThroughSessionID else {
            throw CancellationError()
        }
    }

    func prewarm(isolation: isolated (any Actor)) async {
        let recorder = reusableRecorder ?? factory()
        reusableRecorder = recorder
        await recorder.prewarm()
    }
}
