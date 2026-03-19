import Foundation
import OSLog

enum AppLoggerCategory {
    case general
    case hotkey
    case openAI
    case appBranch
    case permissions
    case dictation

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
        guard shouldEmit(category: category) else { return }
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

    nonisolated static func shouldEmit(
        category: AppLoggerCategory,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let key = category.preferenceKey else {
            return true
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

        if Self.terminalStages.contains(stage) {
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

    private static let terminalStages: Set<Stage> = [
        .listeningStateEntered,
        .failed,
        .cancelled,
    ]
}
