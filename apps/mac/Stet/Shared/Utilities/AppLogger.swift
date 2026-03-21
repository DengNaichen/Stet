import Foundation
import OSLog

enum AppLoggerCategory {
    case general
    case hotkey
    case openAI
    case appBranch
    case permissions
    case dictation
    case perfTrace

    nonisolated var label: String {
        switch self {
        case .general:
            return "general"
        case .hotkey:
            return "hotkey"
        case .openAI:
            return "openai"
        case .appBranch:
            return "app-branch"
        case .permissions:
            return "permissions"
        case .dictation:
            return "dictation"
        case .perfTrace:
            return "perftrace"
        }
    }

    nonisolated var preferenceKey: String? {
        switch self {
        case .general:
            return nil
        case .hotkey:
            return MacPreferences.hotkeyDebugLoggingEnabled
        case .openAI:
            return MacPreferences.openAIDebugLoggingEnabled
        case .appBranch, .permissions, .dictation:
            return nil
        case .perfTrace:
            return MacPreferences.dictationPerfTracingEnabled
        }
    }
}

enum AppLogger {
    private enum Level {
        case info
        case warning
        case error
    }

    nonisolated private static let subsystem = Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet"

    nonisolated static func info(
        _ message: @autoclosure () -> String,
        category: AppLoggerCategory = .general
    ) {
        log(level: .info, message(), category: category)
    }

    nonisolated static func warning(
        _ message: @autoclosure () -> String,
        category: AppLoggerCategory = .general
    ) {
        log(level: .warning, message(), category: category)
    }

    nonisolated static func error(
        _ message: @autoclosure () -> String,
        category: AppLoggerCategory = .general
    ) {
        log(level: .error, message(), category: category)
    }

    nonisolated private static func log(level: Level, _ message: String, category: AppLoggerCategory) {
        guard shouldEmit(level: level, category: category) else { return }
        let logger = Logger(subsystem: subsystem, category: category.label)

        switch level {
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }
    }
    
    nonisolated private static func shouldEmit(
        level: Level,
        category: AppLoggerCategory,
        defaults: UserDefaults = .standard
    ) -> Bool {
        switch level {
        case .warning, .error:
            return true
        case .info:
            break
        }

        guard let key = category.preferenceKey else {
            return false
        }

        return defaults.object(forKey: key) as? Bool ?? false
    }
}

actor DictationLatencyProbe {
    enum Stage: String, Hashable {
        case recordingFinished = "recording_finished"
        case uploadStarted = "upload_started"
        case uploadCompleted = "upload_completed"
        case transcriptionStarted = "transcription_started"
        case transcriptionCompleted = "transcription_completed"
        case transcriptionFailed = "transcription_failed"
        case systemWriteCompleted = "system_write_completed"
        case systemWriteSkipped = "system_write_skipped"
        case systemWriteFailed = "system_write_failed"
    }

    private struct Session {
        let id: String
        let recordingFinishedAt: TimeInterval
        var lastStageAt: TimeInterval
        var reachedStages: Set<Stage> = []
    }

    static let shared = DictationLatencyProbe()

    private var activeSession: Session?

    func beginSession(audioDurationSeconds: TimeInterval?) {
        let now = ProcessInfo.processInfo.systemUptime
        let id = String(UUID().uuidString.prefix(8))
        activeSession = Session(
            id: id,
            recordingFinishedAt: now,
            lastStageAt: now,
            reachedStages: [.recordingFinished]
        )

        let audioDurationDescription: String
        if let audioDurationSeconds, audioDurationSeconds.isFinite, audioDurationSeconds >= 0 {
            audioDurationDescription = String(format: "%.3f", audioDurationSeconds)
        } else {
            audioDurationDescription = "unknown"
        }

        AppLogger.info(
            "LatencyTrace id=\(id) stage=\(Stage.recordingFinished.rawValue) sinceRecordingFinishedMs=0 sincePreviousStageMs=0 audioDurationSeconds=\(audioDurationDescription)",
            category: .dictation
        )
    }

    func record(_ stage: Stage, note: String? = nil) {
        guard var session = activeSession else { return }
        guard !session.reachedStages.contains(stage) else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let sinceRecordingFinishedMs = (now - session.recordingFinishedAt) * 1_000
        let sincePreviousStageMs = (now - session.lastStageAt) * 1_000

        session.lastStageAt = now
        session.reachedStages.insert(stage)
        activeSession = session

        let roundedSinceRecordingFinished = String(format: "%.1f", sinceRecordingFinishedMs)
        let roundedSincePreviousStage = String(format: "%.1f", sincePreviousStageMs)
        let noteSuffix = note.map { " note=\($0)" } ?? ""

        AppLogger.info(
            "LatencyTrace id=\(session.id) stage=\(stage.rawValue) sinceRecordingFinishedMs=\(roundedSinceRecordingFinished) sincePreviousStageMs=\(roundedSincePreviousStage)\(noteSuffix)",
            category: .dictation
        )

        if Self.terminalStages.contains(stage) {
            activeSession = nil
        }
    }

    func ensureUploadCompleted(note: String? = nil) {
        record(.uploadCompleted, note: note)
        record(.transcriptionStarted, note: "inferred_after_upload_completion")
    }

    private static let terminalStages: Set<Stage> = [
        .transcriptionFailed,
        .systemWriteCompleted,
        .systemWriteSkipped,
        .systemWriteFailed,
    ]
}

actor DictationStartupProbe {
    enum Trigger: String {
        case hotkey
        case interface
    }

    enum Stage: String, Hashable {
        case triggerReceived = "trigger_received"
        case permissionsVerified = "permissions_verified"
        case panelShown = "panel_shown"
        case pipelineReady = "pipeline_ready"
        case microphonePermissionResolved = "microphone_permission_resolved"
        case audioCaptureStarted = "audio_capture_started"
        case firstBufferWritten = "first_buffer_written"
        case listeningStateEntered = "listening_state_entered"
        case failed = "failed"
        case cancelled = "cancelled"
    }

    private struct Session {
        let id: String
        let trigger: Trigger
        let startedAt: TimeInterval
        var lastStageAt: TimeInterval
        var reachedStages: Set<Stage> = []
    }

    static let shared = DictationStartupProbe()

    private var activeSession: Session?
    private let traceFileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("stet-startup-trace")
        .appendingPathExtension("log")

    func begin(trigger: Trigger) {
        let now = ProcessInfo.processInfo.systemUptime
        let id = String(UUID().uuidString.prefix(8))
        activeSession = Session(
            id: id,
            trigger: trigger,
            startedAt: now,
            lastStageAt: now,
            reachedStages: [.triggerReceived]
        )

        emitTraceLine(
            "StartupTrace id=\(id) trigger=\(trigger.rawValue) stage=\(Stage.triggerReceived.rawValue) sinceStartMs=0 sincePreviousStageMs=0"
        )
    }

    func record(_ stage: Stage, note: String? = nil) {
        guard var session = activeSession else { return }
        guard !session.reachedStages.contains(stage) else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let sinceStartMs = (now - session.startedAt) * 1_000
        let sincePreviousStageMs = (now - session.lastStageAt) * 1_000

        session.lastStageAt = now
        session.reachedStages.insert(stage)
        activeSession = session

        let roundedSinceStart = String(format: "%.1f", sinceStartMs)
        let roundedSincePreviousStage = String(format: "%.1f", sincePreviousStageMs)
        let noteSuffix = note.map { " note=\($0)" } ?? ""

        emitTraceLine(
            "StartupTrace id=\(session.id) trigger=\(session.trigger.rawValue) stage=\(stage.rawValue) sinceStartMs=\(roundedSinceStart) sincePreviousStageMs=\(roundedSincePreviousStage)\(noteSuffix)"
        )

        if Self.shouldEndSession(afterRecording: stage, reachedStages: session.reachedStages) {
            activeSession = nil
        }
    }

    func resetTraceFile() {
        try? FileManager.default.removeItem(at: traceFileURL)
    }

    func traceFilePath() -> String {
        traceFileURL.path
    }

    private func emitTraceLine(_ line: String) {
        AppLogger.info(line, category: .dictation)
        appendTraceLine(line)
    }

    private func appendTraceLine(_ line: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let payload = "\(timestamp) \(line)\n"

        if !FileManager.default.fileExists(atPath: traceFileURL.path) {
            FileManager.default.createFile(atPath: traceFileURL.path, contents: nil)
        }

        guard let data = payload.data(using: .utf8) else { return }

        do {
            let handle = try FileHandle(forWritingTo: traceFileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            AppLogger.error(
                "Failed to append startup trace file: \(error.localizedDescription)",
                category: .dictation
            )
        }
    }

    private static func shouldEndSession(afterRecording stage: Stage, reachedStages: Set<Stage>) -> Bool {
        if stage == .failed || stage == .cancelled {
            return true
        }

        let completedSuccessStages: Set<Stage> = [
            .firstBufferWritten,
            .listeningStateEntered,
        ]

        return completedSuccessStages.isSubset(of: reachedStages)
    }
}

actor DictationRuntimeProbe {
    enum Stage: String, Hashable {
        case runBegan = "run_began"
        case runEnded = "run_ended"
        case appStateChange = "app_state_change"
        case actionDispatched = "action_dispatched"
        case stateTransition = "state_transition"
        case resultHandled = "result_handled"
        case panelShown = "panel_shown"
        case panelHidden = "panel_hidden"
        case pendingCopyDismissed = "pending_copy_dismissed"
        case pendingCopyCommitted = "pending_copy_committed"
        case captureStartRequested = "capture_start_requested"
        case captureStopRequested = "capture_stop_requested"
        case captureStarted = "capture_started"
        case captureStopped = "capture_stopped"
        case captureCancelled = "capture_cancelled"
        case captureStartError = "capture_start_error"
        case audioStopRequested = "audio_stop_requested"
        case meteringStarted = "metering_started"
        case meteringStopped = "metering_stopped"
    }

    private struct Run {
        let id: String
        let trigger: String
        let source: String
        let panelWasVisibleAtStart: Bool
        var startedAt: TimeInterval
        var lastEventAt: TimeInterval
    }

    private static let maxAdditionalLength = 180
    private var activeRun: Run?
    private var runCounter = 0

    static let shared = DictationRuntimeProbe()

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: MacPreferences.dictationPerfTracingEnabled)
    }

    func beginRun(trigger: String, source: String, panelVisible: Bool) {
        guard isEnabled else { return }
        guard activeRun == nil else { return }

        let now = ProcessInfo.processInfo.systemUptime
        runCounter += 1
        let id = String(format: "run_%04d_%d", runCounter, Int(now))
        activeRun = Run(
            id: id,
            trigger: trigger,
            source: source,
            panelWasVisibleAtStart: panelVisible,
            startedAt: now,
            lastEventAt: now
        )

        emit(
            runId: id,
            stage: .runBegan,
            at: now,
            details: "trigger=\(trigger) source=\(source) panelVisible=\(panelVisible)"
        )
    }

    func endRun(reason: String, details: String? = nil) {
        guard isEnabled, let run = activeRun else { return }
        let now = ProcessInfo.processInfo.systemUptime
        emit(
            runId: run.id,
            stage: .runEnded,
            at: now,
            details: joinDetails(["reason=\(reason)", details])
        )
        activeRun = nil
    }

    func markAppStateChange(from: String, to: String) {
        Task {
            await log(.appStateChange, details: "from=\(from) to=\(to)")
        }
    }

    func markAction(_ action: String, details: String? = nil) {
        Task {
            await log(.actionDispatched, details: "action=\(action)\(details.map { " \($0)" } ?? "")")
        }
    }

    func markPanelShown() {
        Task { await log(.panelShown) }
    }

    func markPanelHidden() {
        Task { await log(.panelHidden) }
    }

    func markPendingCopyDismissed() {
        Task { await log(.pendingCopyDismissed) }
    }

    func markPendingCopyCommitted() {
        Task { await log(.pendingCopyCommitted) }
    }

    func markStateTransition(from: DictationState, to: DictationState) {
        let fromLabel = stateLabel(from)
        let toLabel = stateLabel(to)
        Task {
            await log(.stateTransition, details: "from=\(fromLabel) to=\(toLabel)")
        }
    }

    func markResultHandled(clipboardPending: Bool, textLength: Int) {
        Task {
            await log(
                .resultHandled,
                details: "clipboardPending=\(clipboardPending) textLength=\(textLength)"
            )
        }
    }

    func markCaptureStartRequested() {
        Task { await log(.captureStartRequested) }
    }

    func markCaptureStopRequested() {
        Task { await log(.captureStopRequested) }
    }

    func markCaptureStarted() {
        Task { await log(.captureStarted) }
    }

    func markCaptureStopped() {
        Task { await log(.captureStopped) }
    }

    func markCaptureCancelled() {
        Task { await log(.captureCancelled) }
    }

    func markCaptureStartError(_ message: String) {
        Task {
            await log(.captureStartError, details: message)
        }
    }

    func markAudioStopRequested() {
        Task { await log(.audioStopRequested) }
    }

    func markMeteringStarted() {
        Task { await log(.meteringStarted) }
    }

    func markMeteringStopped() {
        Task { await log(.meteringStopped) }
    }

    private func log(_ stage: Stage, details: String? = nil) async {
        guard isEnabled else { return }
        guard var run = activeRun else { return }

        let now = ProcessInfo.processInfo.systemUptime
        emit(
            runId: run.id,
            stage: stage,
            at: now,
            details: details.map { clamp($0) }
        )
        run.lastEventAt = now
        activeRun = run
    }

    private func emit(
        runId: String,
        stage: Stage,
        at now: TimeInterval,
        details: String? = nil
    ) {
        guard isEnabled else { return }

        guard let run = activeRun else {
            return
        }

        let sinceRunMs = (now - run.startedAt) * 1_000
        let sinceLastMs = (now - run.lastEventAt) * 1_000
        let detailsSuffix = details.map { " \(clamp($0))" } ?? ""

        AppLogger.info(
            """
            RuntimeTrace id=\(runId) stage=\(stage.rawValue) \
            sinceRunMs=\(String(format: "%.1f", sinceRunMs)) \
            sincePrevMs=\(String(format: "%.1f", sinceLastMs)) \
            source=\(run.source) panelAtStart=\(run.panelWasVisibleAtStart)\(detailsSuffix)
            """,
            category: .perfTrace
        )
    }

    private func stateLabel(_ state: DictationState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .starting:
            return "starting"
        case .listening:
            return "listening"
        case .processing:
            return "processing"
        case .result:
            return "result"
        case .clipboardPending:
            return "clipboardPending"
        case .error:
            return "error"
        }
    }

    private func clamp(_ value: String) -> String {
        if value.count <= Self.maxAdditionalLength {
            return value
        }

        let prefix = value.startIndex
        let suffix = value.index(prefix, offsetBy: Self.maxAdditionalLength)
        return String(value[prefix..<suffix]) + "…"
    }

    private func joinDetails(_ values: [String?]) -> String {
        values.compactMap { $0 }.joined(separator: " ")
    }
}
