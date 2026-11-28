import AVFoundation
import Foundation
import StetCore

@MainActor
protocol DictationActivityRecording: AnyObject {
    func recordCompletedSession(
        rawText: String,
        llmText: String?,
        finalText: String,
        startedAt: Date,
        completedAt: Date,
        durationSeconds: Double
    )
}

@MainActor
final class NoOpDictationActivityRecorder: DictationActivityRecording {
    func recordCompletedSession(
        rawText _: String,
        llmText _: String?,
        finalText _: String,
        startedAt _: Date,
        completedAt _: Date,
        durationSeconds _: Double
    ) {}
}

@MainActor
final class SyncedDictationActivityRecorder: DictationActivityRecording {
    typealias HistoryRecorder =
        @MainActor (
            _ rawText: String,
            _ llmText: String?,
            _ finalText: String,
            _ targetBundleID: String?,
            _ targetAppName: String?,
            _ timestamp: Date
        ) -> Void

    private let recordHistory: HistoryRecorder
    private let statsModel: DictationStatsModel
    private let bundleIdentifier: String?
    private let appName: String
    private let asyncStatsRecording: Bool

    init(
        historyService: DictationHistoryService? = nil,
        statsModel: DictationStatsModel = .shared,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        appName: String = "Stet iOS",
        asyncStatsRecording: Bool = true
    ) {
        let resolvedHistoryService = historyService ?? .shared
        self.recordHistory = { rawText, llmText, finalText, bundleID, targetAppName, timestamp in
            _ = resolvedHistoryService.recordCompleted(
                rawText: rawText,
                llmText: llmText,
                finalText: finalText,
                targetBundleID: bundleID,
                targetAppName: targetAppName,
                timestamp: timestamp,
                status: .completed
            )
        }
        self.statsModel = statsModel
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.asyncStatsRecording = asyncStatsRecording
    }

    init(
        recordHistory: @escaping HistoryRecorder,
        statsModel: DictationStatsModel,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        appName: String = "Stet iOS",
        asyncStatsRecording: Bool = false
    ) {
        self.recordHistory = recordHistory
        self.statsModel = statsModel
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.asyncStatsRecording = asyncStatsRecording
    }

    func recordCompletedSession(
        rawText: String,
        llmText: String?,
        finalText: String,
        startedAt: Date,
        completedAt: Date,
        durationSeconds: Double
    ) {
        let trimmedRaw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFinal = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty, !trimmedFinal.isEmpty else { return }

        let trimmedLLM = llmText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let recordedLLM = trimmedLLM?.isEmpty == false ? trimmedLLM : nil

        recordHistory(trimmedRaw, recordedLLM, trimmedFinal, bundleIdentifier, appName, completedAt)

        let wordCount = DictationWordCounter.displayUnits(in: trimmedFinal)
        let normalizedDuration = max(0, durationSeconds)
        let statsModel = self.statsModel
        let bundleIdentifier = self.bundleIdentifier
        let appName = self.appName
        if asyncStatsRecording {
            Task.detached(priority: .utility) {
                statsModel.record(
                    startedAt: startedAt,
                    durationSeconds: normalizedDuration,
                    wordCount: wordCount,
                    targetBundleID: bundleIdentifier,
                    targetAppName: appName,
                    sourcePlatform: "iOS"
                )
            }
        } else {
            statsModel.record(
                startedAt: startedAt,
                durationSeconds: normalizedDuration,
                wordCount: wordCount,
                targetBundleID: bundleIdentifier,
                targetAppName: appName,
                sourcePlatform: "iOS"
            )
        }
    }
}

nonisolated struct MobileASREngineFailure: Sendable {
    let sessionId: String?
    let message: String
}

@MainActor
protocol MobileASREngineFailureReporting: AnyObject {
    var failureStream: AsyncStream<MobileASREngineFailure> { get }
}

enum DictationCoordinatorPhase: Equatable, Sendable {
    case inactive
    case loading
    case idle
    case standby
    case starting(sessionId: String)
    case recording(sessionId: String)
    case transcribing(sessionId: String)
    case rewriting(sessionId: String)
    case failed(message: String)
}

enum DictationCoordinatorEvent: Sendable {
    case loading
    case ready(engineName: String)
    case standby
    case starting(sessionId: String)
    case recording(sessionId: String)
    case transcribing(sessionId: String)
    case rewriting(sessionId: String)
    case partialTranscript(sessionId: String, text: String)
    case completed(sessionId: String, text: String, metrics: ASRMetrics?)
    case failed(sessionId: String?, message: String)
}

@MainActor
protocol DictationSessionCoordinating: AnyObject {
    var events: AsyncStream<DictationCoordinatorEvent> { get }
    var phase: DictationCoordinatorPhase { get }

    func start()
    func recoverAudioSession()
    func updateIdleStandbyTimeout(_ timeout: Duration?)
    func synchronizeKeyboardCommands()
    func startRecording(sessionId: String)
    func stopRecording(sessionId: String?)
    func cancelRecording(sessionId: String)
    func shutdown() async
}

@MainActor
final class DictationSessionCoordinator: DictationSessionCoordinating {
    typealias ResourcePreparation = @MainActor () async throws -> Void

    let events: AsyncStream<DictationCoordinatorEvent>
    private(set) var phase: DictationCoordinatorPhase = .inactive

    private let continuation: AsyncStream<DictationCoordinatorEvent>.Continuation
    private let engine: any ASREngine
    private let prepareResources: ResourcePreparation
    private let permissionProvider: any MicrophonePermissionProviding
    private let sessionStore: any DictationSessionPersisting
    private let postProcessor: any TranscriptPostProcessing
    private let commandMonitor: any KeyboardCommandMonitoring
    private let notificationCenter: NotificationCenter
    private let rewriteHeartbeatInterval: Duration
    private let timingStore: DictationTimingStore
    private let activityRecorder: any DictationActivityRecording

    private struct SessionTimingDraft {
        let sessionId: String
        var startedAtDate: Date
        var startRequestedAt: TimeInterval
        var recordingStartedAt: TimeInterval?
        var startMs: Int = 0
        var stopRequestedAt: TimeInterval?
        var localFinalizeMs: Int = 0
        var rewriteMs: Int?
    }

    private var activeSessionId: String?
    private var timingDraft: SessionTimingDraft?
    private var isStarted = false
    private var isCommandMonitorRunning = false
    private var lifecycleGeneration = UUID()
    private var bootstrapGeneration: UUID?
    private var recoveryGeneration: UUID?
    private var startGeneration: UUID?
    private var rewriteGeneration: UUID?
    private var idleStandbyTimeout: Duration?
    private var idleStandbyGeneration: UUID?
    private var requiresAudioEngineReset = false

    private var bootstrapTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var rewriteTask: Task<Void, Never>?
    private var idleStandbyTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var failuresTask: Task<Void, Never>?
    private var commandsTask: Task<Void, Never>?
    private var audioSessionObservers: [NSObjectProtocol] = []

    init(
        engine: any ASREngine,
        prepareResources: @escaping ResourcePreparation = {},
        permissionProvider: any MicrophonePermissionProviding,
        sessionStore: any DictationSessionPersisting,
        postProcessor: any TranscriptPostProcessing,
        commandMonitor: any KeyboardCommandMonitoring,
        notificationCenter: NotificationCenter = .default,
        rewriteHeartbeatInterval: Duration = .seconds(2),
        idleStandbyTimeout: Duration? = nil,
        timingStore: DictationTimingStore? = nil,
        activityRecorder: (any DictationActivityRecording)? = nil
    ) {
        self.engine = engine
        self.prepareResources = prepareResources
        self.permissionProvider = permissionProvider
        self.sessionStore = sessionStore
        self.postProcessor = postProcessor
        self.commandMonitor = commandMonitor
        self.notificationCenter = notificationCenter
        self.rewriteHeartbeatInterval = rewriteHeartbeatInterval
        self.idleStandbyTimeout = idleStandbyTimeout
        self.timingStore = timingStore ?? .shared
        self.activityRecorder = activityRecorder ?? SyncedDictationActivityRecorder()
        (events, continuation) = AsyncStream.makeStream()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        lifecycleGeneration = UUID()
        listenForResults()
        listenForEngineFailures()
        listenForKeyboardCommands()
        registerAudioSessionObservers()
        commandMonitor.start()
        isCommandMonitorRunning = true
        bootstrap()
    }

    func updateIdleStandbyTimeout(_ timeout: Duration?) {
        idleStandbyTimeout = timeout
        guard isStarted else { return }
        switch phase {
        case .idle:
            scheduleIdleStandbyTimer()
        case .standby where timeout == nil:
            recoverAudioSession()
        default:
            break
        }
    }

    func recoverAudioSession() {
        guard isStarted else { return }
        if case .failed = phase {
            bootstrap()
            return
        }
        guard phase == .idle || phase == .standby else { return }

        guard bootstrapTask == nil,
            recoveryTask == nil,
            startTask == nil
        else { return }
        cancelIdleStandbyTimer()
        let generation = UUID()
        let lifecycle = lifecycleGeneration
        recoveryGeneration = generation
        phase = .loading
        continuation.yield(.loading)
        recoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.recoveryGeneration == generation {
                    self.recoveryGeneration = nil
                    self.recoveryTask = nil
                }
            }

            do {
                try await self.prepareEngine()
                guard self.isCurrent(lifecycle: lifecycle),
                    self.recoveryGeneration == generation,
                    !Task.isCancelled
                else { return }
                self.phase = .idle
                self.scheduleIdleStandbyTimer()
                self.continuation.yield(.ready(engineName: self.engine.name))
                if !self.isCommandMonitorRunning {
                    self.commandMonitor.start()
                    self.isCommandMonitorRunning = true
                }
                self.commandMonitor.pollNow(force: true)
            } catch {
                guard self.isCurrent(lifecycle: lifecycle),
                    self.recoveryGeneration == generation,
                    !Task.isCancelled
                else { return }
                self.fail(sessionId: nil, message: error.localizedDescription)
            }
        }
    }

    func synchronizeKeyboardCommands() {
        if phase == .standby {
            recoverAudioSession()
            return
        }
        commandMonitor.pollNow(force: true)
    }

    func startRecording(sessionId: String) {
        guard phase == .idle || phase == .standby,
            startTask == nil,
            recoveryTask == nil,
            sessionStore.claimSessionForStart(sessionId: sessionId)
        else { return }

        cancelIdleStandbyTimer()
        if !isCommandMonitorRunning {
            commandMonitor.start()
            isCommandMonitorRunning = true
        }
        activeSessionId = sessionId
        timingDraft = SessionTimingDraft(
            sessionId: sessionId,
            startedAtDate: Date(),
            startRequestedAt: ProcessInfo.processInfo.systemUptime
        )
        phase = .starting(sessionId: sessionId)
        continuation.yield(.starting(sessionId: sessionId))

        let generation = UUID()
        let lifecycle = lifecycleGeneration
        startGeneration = generation
        startTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.startGeneration == generation {
                    self.startGeneration = nil
                    self.startTask = nil
                    if self.shouldFinishCancelledStart(sessionId: sessionId) {
                        self.phase = .idle
                        self.scheduleIdleStandbyTimer()
                        self.continuation.yield(.ready(engineName: self.engine.name))
                    }
                    if self.phase == .idle {
                        self.commandMonitor.pollNow(force: true)
                    }
                }
            }

            do {
                try await self.engine.start(sessionId: sessionId)
                if var draft = self.timingDraft, draft.sessionId == sessionId {
                    draft.startMs = Self.elapsedMilliseconds(since: draft.startRequestedAt)
                    self.timingDraft = draft
                }
            } catch {
                guard self.isCurrent(lifecycle: lifecycle),
                    self.startGeneration == generation,
                    self.activeSessionId == sessionId,
                    !Task.isCancelled
                else { return }
                self.fail(sessionId: sessionId, message: error.localizedDescription)
                return
            }

            guard self.isCurrent(lifecycle: lifecycle) else { return }
            guard self.startGeneration == generation,
                self.activeSessionId == sessionId,
                !Task.isCancelled
            else {
                self.engine.stop()
                return
            }

            self.finishStartingSession(sessionId: sessionId)
        }
    }

    func stopRecording(sessionId: String?) {
        guard let activeSessionId else {
            reconcileStopWithoutActiveSession(sessionId: sessionId)
            return
        }
        if let sessionId, sessionId != activeSessionId { return }

        switch phase {
        case .starting:
            markStopTimestampIfNeeded(for: activeSessionId)
            let didTransition = sessionStore.transitionState(
                for: activeSessionId,
                from: [.requestStart],
                to: .requestStop,
                error: nil
            )
            if !didTransition {
                guard let session = sessionStore.getSession(),
                    session.sessionId == activeSessionId,
                    session.state == .requestStop
                else {
                    relinquishSession(sessionId: activeSessionId)
                    return
                }
            }
            guard self.activeSessionId == activeSessionId else {
                return
            }
            phase = .transcribing(sessionId: activeSessionId)
            continuation.yield(.transcribing(sessionId: activeSessionId))

        case .recording:
            markStopTimestampIfNeeded(for: activeSessionId)
            guard markTranscribing(sessionId: activeSessionId) else { return }
            engine.stop()

        default:
            break
        }
    }

    func cancelRecording(sessionId: String) {
        guard activeSessionId == sessionId else { return }

        let isSettlingStart = startTask != nil
        activeSessionId = nil
        timingDraft = nil
        startTask?.cancel()
        rewriteTask?.cancel()
        rewriteGeneration = nil
        rewriteTask = nil
        engine.stop()
        guard !isSettlingStart else { return }
        phase = .idle
        scheduleIdleStandbyTimer()
        continuation.yield(.ready(engineName: engine.name))
    }

    func shutdown() async {
        guard isStarted else { return }
        isStarted = false
        lifecycleGeneration = UUID()

        let tasks = [
            bootstrapTask,
            recoveryTask,
            startTask,
            rewriteTask,
            idleStandbyTask,
            resultsTask,
            failuresTask,
            commandsTask,
        ].compactMap { $0 }

        for task in tasks {
            task.cancel()
        }

        commandMonitor.stop()
        isCommandMonitorRunning = false
        for observer in audioSessionObservers {
            notificationCenter.removeObserver(observer)
        }
        audioSessionObservers.removeAll()
        activeSessionId = nil
        bootstrapGeneration = nil
        recoveryGeneration = nil
        startGeneration = nil
        rewriteGeneration = nil
        idleStandbyGeneration = nil
        phase = .inactive

        for task in tasks {
            await task.value
        }

        bootstrapTask = nil
        recoveryTask = nil
        startTask = nil
        rewriteTask = nil
        idleStandbyTask = nil
        resultsTask = nil
        failuresTask = nil
        commandsTask = nil
        engine.teardown()
        continuation.finish()
    }

    private func bootstrap() {
        guard isStarted,
            bootstrapTask == nil,
            recoveryTask == nil,
            startTask == nil
        else { return }
        cancelIdleStandbyTimer()
        phase = .loading
        continuation.yield(.loading)

        let generation = UUID()
        let lifecycle = lifecycleGeneration
        bootstrapGeneration = generation
        bootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.bootstrapGeneration == generation {
                    self.bootstrapGeneration = nil
                    self.bootstrapTask = nil
                }
            }

            do {
                try await self.permissionProvider.requestPermission()
                try await self.prepareResources()
                try await self.prepareEngine()

                guard self.isCurrent(lifecycle: lifecycle),
                    self.bootstrapGeneration == generation,
                    !Task.isCancelled
                else { return }
                self.phase = .idle
                self.scheduleIdleStandbyTimer()
                self.continuation.yield(.ready(engineName: self.engine.name))
                if !self.isCommandMonitorRunning {
                    self.commandMonitor.start()
                    self.isCommandMonitorRunning = true
                }
                self.commandMonitor.pollNow(force: true)
            } catch {
                guard self.isCurrent(lifecycle: lifecycle),
                    self.bootstrapGeneration == generation,
                    !Task.isCancelled
                else { return }
                self.fail(sessionId: nil, message: error.localizedDescription)
            }
        }
    }

    private func listenForResults() {
        let resultStream = engine.resultStream
        resultsTask = Task { @MainActor [weak self] in
            for await result in resultStream {
                guard !Task.isCancelled else { break }
                self?.handle(result)
            }
        }
    }

    private func listenForEngineFailures() {
        guard let failureReportingEngine = engine as? any MobileASREngineFailureReporting else {
            return
        }
        let failures = failureReportingEngine.failureStream
        failuresTask = Task { @MainActor [weak self] in
            for await failure in failures {
                guard !Task.isCancelled else { break }
                self?.handle(failure)
            }
        }
    }

    private func listenForKeyboardCommands() {
        let commands = commandMonitor.commands
        commandsTask = Task { @MainActor [weak self] in
            for await command in commands {
                guard !Task.isCancelled else { break }
                self?.handle(command)
            }
        }
    }

    private func handle(_ command: KeyboardDictationCommand) {
        guard isStarted else { return }

        switch command {
        case .start(let sessionId):
            startRecording(sessionId: sessionId)
        case .stop(let sessionId):
            stopRecording(sessionId: sessionId)
        case .cancel(let sessionId):
            cancelRecording(sessionId: sessionId)
        }
    }

    private func handle(_ result: ASRResult) {
        guard isStarted, activeSessionId == result.sessionId else { return }
        let sessionId = result.sessionId

        if result.isFinal {
            if var draft = timingDraft, draft.sessionId == sessionId, let stopAt = draft.stopRequestedAt {
                draft.localFinalizeMs = Self.elapsedMilliseconds(since: stopAt)
                timingDraft = draft
            }
            finalize(sessionId: sessionId, text: result.text, metrics: result.metrics)
        } else {
            sessionStore.updateText(for: sessionId, partial: result.text, final: "")
            continuation.yield(.partialTranscript(sessionId: sessionId, text: result.text))
        }
    }

    private func handle(_ failure: MobileASREngineFailure) {
        guard isStarted else { return }
        if let sessionId = failure.sessionId, sessionId != activeSessionId {
            return
        }
        fail(sessionId: failure.sessionId, message: failure.message)
    }

    private func finalize(
        sessionId: String,
        text: String,
        metrics: ASRMetrics?
    ) {
        guard activeSessionId == sessionId else { return }

        guard !text.isEmpty else {
            complete(sessionId: sessionId, rawText: text, llmText: nil, text: text, metrics: metrics)
            return
        }

        guard postProcessor.isAvailable else {
            complete(sessionId: sessionId, rawText: text, llmText: nil, text: text, metrics: metrics)
            return
        }

        guard
            sessionStore.transitionState(
                for: sessionId,
                from: [.recording, .requestStop, .transcribing],
                to: .transcribing,
                error: nil
            )
        else {
            relinquishSession(sessionId: sessionId)
            return
        }

        phase = .rewriting(sessionId: sessionId)
        continuation.yield(.rewriting(sessionId: sessionId))
        rewriteTask?.cancel()
        let generation = UUID()
        let lifecycle = lifecycleGeneration
        rewriteGeneration = generation
        rewriteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let heartbeat = Task {
                await self.keepRewriteAlive(sessionId: sessionId, generation: generation)
            }
            defer {
                heartbeat.cancel()
                if self.rewriteGeneration == generation {
                    self.rewriteGeneration = nil
                    self.rewriteTask = nil
                }
            }

            let rewriteStartedAt = ProcessInfo.processInfo.systemUptime
            let outcome = await self.postProcessor.processWithOutcome(text)
            if var draft = self.timingDraft, draft.sessionId == sessionId {
                draft.rewriteMs = Self.elapsedMilliseconds(since: rewriteStartedAt)
                self.timingDraft = draft
            }
            guard self.isCurrent(lifecycle: lifecycle),
                self.rewriteGeneration == generation,
                !Task.isCancelled,
                self.activeSessionId == sessionId
            else { return }
            self.complete(
                sessionId: sessionId,
                rawText: text,
                llmText: outcome.didRewrite ? outcome.text : nil,
                text: outcome.text,
                metrics: metrics
            )
        }
    }

    private func keepRewriteAlive(sessionId: String, generation: UUID) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: rewriteHeartbeatInterval)
            } catch {
                return
            }
            guard !Task.isCancelled, rewriteGeneration == generation,
                phase == .rewriting(sessionId: sessionId),
                sessionStore.transitionState(
                    for: sessionId,
                    from: [.transcribing],
                    to: .transcribing,
                    error: nil
                )
            else { return }
        }
    }

    private func complete(
        sessionId: String,
        rawText: String,
        llmText: String?,
        text: String,
        metrics: ASRMetrics?
    ) {
        guard activeSessionId == sessionId else { return }
        guard
            sessionStore.completeSession(
                for: sessionId,
                from: [.recording, .requestStop, .transcribing],
                finalText: text
            )
        else {
            relinquishSession(sessionId: sessionId)
            return
        }

        let completedAt = Date()
        let activeDraft = timingDraft?.sessionId == sessionId ? timingDraft : nil
        let startedAt = activeDraft?.startedAtDate ?? completedAt
        let durationSeconds = resolvedDurationSeconds(
            metrics: metrics,
            draft: activeDraft,
            startedAt: startedAt,
            completedAt: completedAt
        )

        recordCompletedTiming(sessionId: sessionId, metrics: metrics)
        activeSessionId = nil
        timingDraft = nil
        phase = .idle
        scheduleIdleStandbyTimer()
        continuation.yield(.completed(sessionId: sessionId, text: text, metrics: metrics))
        commandMonitor.pollNow(force: true)

        activityRecorder.recordCompletedSession(
            rawText: rawText,
            llmText: llmText,
            finalText: text,
            startedAt: startedAt,
            completedAt: completedAt,
            durationSeconds: durationSeconds
        )
    }

    private func resolvedDurationSeconds(
        metrics: ASRMetrics?,
        draft: SessionTimingDraft?,
        startedAt: Date,
        completedAt: Date
    ) -> Double {
        if let audioDuration = metrics?.audioDuration, audioDuration > 0 {
            return audioDuration
        }
        if let draft {
            let startUptime = draft.recordingStartedAt ?? draft.startRequestedAt
            let endUptime = draft.stopRequestedAt ?? ProcessInfo.processInfo.systemUptime
            return max(0, endUptime - startUptime)
        }
        return max(0, completedAt.timeIntervalSince(startedAt))
    }

    private func markStopTimestampIfNeeded(for sessionId: String) {
        guard var draft = timingDraft, draft.sessionId == sessionId, draft.stopRequestedAt == nil else {
            return
        }
        draft.stopRequestedAt = ProcessInfo.processInfo.systemUptime
        timingDraft = draft
    }

    private func recordCompletedTiming(sessionId: String, metrics: ASRMetrics?) {
        guard let draft = timingDraft, draft.sessionId == sessionId else { return }
        let totalWaitMs: Int
        if let stopAt = draft.stopRequestedAt {
            totalWaitMs = Self.elapsedMilliseconds(since: stopAt)
        } else {
            totalWaitMs = draft.localFinalizeMs + (draft.rewriteMs ?? 0)
        }
        let audioDurationMs = metrics.map { max(0, Int(($0.audioDuration * 1_000).rounded())) }
        timingStore.record(
            DictationTimingRecord(
                id: sessionId,
                recordedAt: Date(),
                audioDurationMs: audioDurationMs,
                startMs: draft.startMs,
                localFinalizeMs: draft.localFinalizeMs,
                rewriteMs: draft.rewriteMs,
                totalWaitMs: totalWaitMs
            )
        )
    }

    private static func elapsedMilliseconds(since startedAt: TimeInterval) -> Int {
        max(0, Int(((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000).rounded()))
    }

    @discardableResult
    private func markTranscribing(sessionId: String) -> Bool {
        guard activeSessionId == sessionId else { return false }
        let didTransition = sessionStore.transitionState(
            for: sessionId,
            from: [.recording, .requestStop],
            to: .transcribing,
            error: nil
        )
        if !didTransition {
            guard let session = sessionStore.getSession(),
                session.sessionId == sessionId,
                session.state == .transcribing
            else {
                relinquishSession(sessionId: sessionId)
                return false
            }
        }

        phase = .transcribing(sessionId: sessionId)
        continuation.yield(.transcribing(sessionId: sessionId))
        return true
    }

    private func fail(sessionId: String?, message: String) {
        guard isStarted else { return }
        let targetSessionId = sessionId ?? activeSharedSessionId()
        if let targetSessionId {
            sessionStore.transitionState(
                for: targetSessionId,
                from: [.requestStart, .launching, .warming, .recording, .requestStop, .transcribing],
                to: .failed,
                error: message
            )
        }
        if activeSessionId != nil {
            engine.stop()
        }
        cancelIdleStandbyTimer()
        startTask?.cancel()
        rewriteTask?.cancel()
        rewriteTask = nil
        rewriteGeneration = nil
        activeSessionId = nil
        phase = .failed(message: message)
        continuation.yield(.failed(sessionId: sessionId, message: message))
    }

    private func finishStartingSession(sessionId: String) {
        guard activeSessionId == sessionId,
            let session = sessionStore.getSession(),
            session.sessionId == sessionId
        else {
            engine.stop()
            relinquishSession(sessionId: sessionId)
            return
        }

        switch session.state {
        case .requestStart:
            guard
                sessionStore.transitionState(
                    for: sessionId,
                    from: [.requestStart],
                    to: .recording,
                    error: nil
                )
            else {
                resolveChangedSessionAfterStart(sessionId: sessionId)
                return
            }
            if var draft = timingDraft, draft.sessionId == sessionId {
                draft.startedAtDate = Date()
                draft.recordingStartedAt = ProcessInfo.processInfo.systemUptime
                timingDraft = draft
            }
            phase = .recording(sessionId: sessionId)
            continuation.yield(.recording(sessionId: sessionId))
            postProcessor.prewarm()

        case .requestStop:
            if markTranscribing(sessionId: sessionId) {
                engine.stop()
            }

        case .cancelled:
            engine.stop()
            relinquishSession(sessionId: sessionId)

        default:
            engine.stop()
            relinquishSession(sessionId: sessionId)
        }
    }

    private func resolveChangedSessionAfterStart(sessionId: String) {
        guard let session = sessionStore.getSession(), session.sessionId == sessionId else {
            engine.stop()
            relinquishSession(sessionId: sessionId)
            return
        }

        if session.state == .requestStop, markTranscribing(sessionId: sessionId) {
            engine.stop()
        } else {
            engine.stop()
            relinquishSession(sessionId: sessionId)
        }
    }

    private func relinquishSession(sessionId: String) {
        guard activeSessionId == sessionId else { return }
        activeSessionId = nil
        phase = .idle
        scheduleIdleStandbyTimer()
        continuation.yield(.ready(engineName: engine.name))
        commandMonitor.pollNow(force: true)
    }

    private func scheduleIdleStandbyTimer() {
        cancelIdleStandbyTimer()
        guard isStarted, phase == .idle, let timeout = idleStandbyTimeout else { return }

        let generation = UUID()
        let lifecycle = lifecycleGeneration
        idleStandbyGeneration = generation
        idleStandbyTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            guard let self,
                self.isCurrent(lifecycle: lifecycle),
                self.idleStandbyGeneration == generation,
                !Task.isCancelled
            else { return }
            self.enterStandby()
        }
    }

    private func cancelIdleStandbyTimer() {
        idleStandbyGeneration = nil
        idleStandbyTask?.cancel()
        idleStandbyTask = nil
    }

    private func enterStandby() {
        guard isStarted,
            phase == .idle,
            activeSessionId == nil,
            bootstrapTask == nil,
            recoveryTask == nil,
            startTask == nil
        else { return }
        cancelIdleStandbyTimer()
        commandMonitor.stop()
        isCommandMonitorRunning = false
        sessionStore.clearHeartbeat()
        engine.suspendAudio()
        phase = .standby
        continuation.yield(.standby)
    }

    private func isCurrent(lifecycle: UUID) -> Bool {
        isStarted && lifecycleGeneration == lifecycle
    }

    private func activeSharedSessionId() -> String? {
        guard let session = sessionStore.getSession() else { return nil }

        switch session.state {
        case .requestStart, .launching, .warming, .recording, .requestStop, .transcribing:
            return session.sessionId
        default:
            return nil
        }
    }

    private func registerAudioSessionObservers() {
        let interruptionObserver = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let info = notification.userInfo,
                let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: typeRaw),
                type == .ended,
                let self
            else { return }
            Task { @MainActor [self] in
                self.handleAudioSessionInvalidation(
                    message: "The audio session was interrupted. Please try again."
                )
            }
        }

        let resetObserver = notificationCenter.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.handleAudioSessionInvalidation(
                    message: "Audio services were reset. Please try again.",
                    requiresEngineReset: true
                )
            }
        }

        audioSessionObservers = [interruptionObserver, resetObserver]
    }

    private func reconcileStopWithoutActiveSession(sessionId: String?) {
        guard let sessionId,
            sessionStore.completeSession(
                for: sessionId,
                from: [.requestStop],
                finalText: ""
            )
        else { return }
        continuation.yield(.completed(sessionId: sessionId, text: "", metrics: nil))
        if phase == .loading {
            continuation.yield(.loading)
        }
        commandMonitor.pollNow(force: true)
    }

    private func shouldFinishCancelledStart(sessionId: String) -> Bool {
        guard activeSessionId == nil else { return false }
        switch phase {
        case .starting(let phaseSessionId), .transcribing(let phaseSessionId):
            return phaseSessionId == sessionId
        default:
            return false
        }
    }

    private func prepareEngine() async throws {
        while true {
            if requiresAudioEngineReset {
                requiresAudioEngineReset = false
                do {
                    try await engine.resetAudio()
                } catch {
                    requiresAudioEngineReset = true
                    throw error
                }
            } else {
                try await engine.prepare()
            }

            guard requiresAudioEngineReset else { return }
        }
    }

    private func handleAudioSessionInvalidation(
        message: String,
        requiresEngineReset: Bool = false
    ) {
        if requiresEngineReset {
            requiresAudioEngineReset = true
        }
        if let activeSessionId {
            fail(sessionId: activeSessionId, message: message)
        } else if phase != .standby {
            recoverAudioSession()
        }
    }
}

@MainActor
final class UnavailableDictationSessionCoordinator: DictationSessionCoordinating {
    let events: AsyncStream<DictationCoordinatorEvent>
    private(set) var phase: DictationCoordinatorPhase

    private let continuation: AsyncStream<DictationCoordinatorEvent>.Continuation
    private let message: String
    private var didStart = false

    init(message: String) {
        self.message = message
        self.phase = .failed(message: message)
        (events, continuation) = AsyncStream.makeStream()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        continuation.yield(.failed(sessionId: nil, message: message))
    }

    func recoverAudioSession() {
        continuation.yield(.failed(sessionId: nil, message: message))
    }

    func updateIdleStandbyTimeout(_ _: Duration?) {}
    func synchronizeKeyboardCommands() {}
    func startRecording(sessionId _: String) {}
    func stopRecording(sessionId _: String?) {}
    func cancelRecording(sessionId _: String) {}
    func shutdown() async {
        continuation.finish()
    }
}
