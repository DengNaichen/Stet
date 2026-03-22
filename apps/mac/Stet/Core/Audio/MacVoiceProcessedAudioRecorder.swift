#if os(macOS)
import AVFoundation
import Foundation

protocol MacRecordingBackendRecorder: Sendable {
    func startRecordingAttempt(
        to fileURL: URL,
        outputFormat: AVAudioFormat,
        attempt: MacCaptureAttemptPlan
    ) throws
    func waitForCapturedAudio(timeout: Duration) async -> Bool
    func activateRecordingWindow() throws
    func stopRecording(writtenFileAt fileURL: URL) async -> MacAudioFileRecordingOutcome
    func cancelRecording()
    func prewarm()
}

extension MacAudioFileRecorder: MacRecordingBackendRecorder {}
extension MacCaptureAudioFileRecorder: MacRecordingBackendRecorder {}

final class MacVoiceProcessedAudioRecorder: @unchecked Sendable {
    private enum Configuration {
        static let nativeFirstCapturedAudioTimeout: Duration = .milliseconds(350)
        static let explicitNativeFirstCapturedAudioTimeout: Duration = .milliseconds(800)
        static let avCaptureFirstCapturedAudioTimeout: Duration = .milliseconds(2_500)
        static let fallbackRetryDelay: Duration = .milliseconds(50)
    }

    private struct ActiveAttempt {
        let backend: MacCaptureBackend
        let recorder: any MacRecordingBackendRecorder
    }

    private let stateLock = NSLock()
    private let nativeRecorder: any MacRecordingBackendRecorder
    private let fallbackRecorder: any MacRecordingBackendRecorder

    private var activeAttempt: ActiveAttempt?

    convenience init(
        audioLevelHandler: @escaping @Sendable (Double) -> Void = { _ in },
        onFirstRecordedBufferWritten: @escaping @Sendable () -> Void = {}
    ) {
        self.init(
            nativeRecorder: MacAudioFileRecorder(
                audioLevelHandler: audioLevelHandler,
                onFirstRecordedBufferWritten: onFirstRecordedBufferWritten
            ),
            fallbackRecorder: MacCaptureAudioFileRecorder(
                audioLevelHandler: audioLevelHandler,
                onFirstRecordedBufferWritten: onFirstRecordedBufferWritten
            )
        )
    }

    init(
        nativeRecorder: any MacRecordingBackendRecorder,
        fallbackRecorder: any MacRecordingBackendRecorder
    ) {
        self.nativeRecorder = nativeRecorder
        self.fallbackRecorder = fallbackRecorder
    }

    func startRecording(to fileURL: URL, outputFormat: AVAudioFormat) async throws {
        precondition(currentAttempt() == nil, "MacVoiceProcessedAudioRecorder is already recording.")

        let candidates = MacRecordingInputDeviceResolver.inputDeviceCandidates()
        var startupError: Error?

        for candidate in candidates {
            let attempts = MacCaptureRouteNegotiator.attemptPlans(for: candidate)

            for attempt in attempts {
                let recorder = recorder(for: attempt.backend)
                let attemptStartedAt = ProcessInfo.processInfo.systemUptime

                do {
                    try recorder.startRecordingAttempt(
                        to: fileURL,
                        outputFormat: outputFormat,
                        attempt: attempt
                    )

                    let readinessTimeout = Self.firstCapturedAudioTimeout(for: attempt)
                    let didObserveAudio = await recorder.waitForCapturedAudio(
                        timeout: readinessTimeout
                    )
                    if didObserveAudio {
                        setCurrentAttempt(
                            ActiveAttempt(
                                backend: attempt.backend,
                                recorder: recorder
                            )
                        )
                        let attemptMs = Self.elapsedMilliseconds(since: attemptStartedAt)
                        AppLogger.info(
                            """
                            Started macOS capture backend. \
                            \(MacCaptureRouteNegotiator.describe(attempt)) \
                            startupMs=\(Self.formatMilliseconds(attemptMs))
                            """,
                            category: .dictation
                        )
                        return
                    }

                    startupError = SpeechServiceError.failedToStart
                    recorder.cancelRecording()
                    let attemptMs = Self.elapsedMilliseconds(since: attemptStartedAt)
                    AppLogger.warning(
                        """
                        macOS capture backend produced no audio before deadline. \
                        \(MacCaptureRouteNegotiator.describe(attempt)) \
                        readinessTimeoutMs=\(Self.formatDurationMilliseconds(readinessTimeout)) \
                        startupMs=\(Self.formatMilliseconds(attemptMs))
                        """,
                        category: .dictation
                    )
                } catch {
                    startupError = error
                    recorder.cancelRecording()
                    let attemptMs = Self.elapsedMilliseconds(since: attemptStartedAt)
                    AppLogger.warning(
                        """
                        macOS capture backend failed. \
                        \(MacCaptureRouteNegotiator.describe(attempt)) \
                        readinessTimeoutMs=\(Self.formatDurationMilliseconds(Self.firstCapturedAudioTimeout(for: attempt))) \
                        startupMs=\(Self.formatMilliseconds(attemptMs)) \
                        error=\(error.localizedDescription)
                        """,
                        category: .dictation
                    )
                }

                try? await Task.sleep(for: Configuration.fallbackRetryDelay)
            }
        }

        AppLogger.error(
            "All macOS capture backends failed. error=\(startupError?.localizedDescription ?? SpeechServiceError.failedToStart.localizedDescription)",
            category: .dictation
        )
        throw startupError ?? SpeechServiceError.failedToStart
    }

    func activateRecordingWindow() throws {
        try currentAttempt()?.recorder.activateRecordingWindow()
    }

    func stopRecording(writtenFileAt fileURL: URL) async -> MacAudioFileRecordingOutcome {
        guard let attempt = clearCurrentAttempt() else {
            return .empty
        }

        return await attempt.recorder.stopRecording(writtenFileAt: fileURL)
    }

    func cancelRecording() {
        if let attempt = clearCurrentAttempt() {
            attempt.recorder.cancelRecording()
            return
        }

        nativeRecorder.cancelRecording()
        fallbackRecorder.cancelRecording()
    }

    func prewarm() {
        nativeRecorder.prewarm()
        fallbackRecorder.prewarm()
    }

    deinit {
        nativeRecorder.cancelRecording()
        fallbackRecorder.cancelRecording()
    }

    private func recorder(for backend: MacCaptureBackend) -> any MacRecordingBackendRecorder {
        switch backend {
        case .nativeVoiceProcessing, .nativeRawEngine:
            return nativeRecorder
        case .avCapture:
            return fallbackRecorder
        }
    }

    private func currentAttempt() -> ActiveAttempt? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeAttempt
    }

    private func setCurrentAttempt(_ attempt: ActiveAttempt) {
        stateLock.lock()
        activeAttempt = attempt
        stateLock.unlock()
    }

    private func clearCurrentAttempt() -> ActiveAttempt? {
        stateLock.lock()
        let attempt = activeAttempt
        activeAttempt = nil
        stateLock.unlock()
        return attempt
    }

    private static func elapsedMilliseconds(since start: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1_000
    }

    private static func firstCapturedAudioTimeout(for attempt: MacCaptureAttemptPlan) -> Duration {
        switch attempt.backend {
        case .avCapture:
            return Configuration.avCaptureFirstCapturedAudioTimeout
        case .nativeVoiceProcessing:
            return Configuration.nativeFirstCapturedAudioTimeout
        case .nativeRawEngine:
            return attempt.explicitBinding
                ? Configuration.explicitNativeFirstCapturedAudioTimeout
                : Configuration.nativeFirstCapturedAudioTimeout
        }
    }

    private static func formatMilliseconds(_ duration: Double) -> String {
        String(format: "%.1f", duration)
    }

    private static func formatDurationMilliseconds(_ duration: Duration) -> String {
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return formatMilliseconds(milliseconds)
    }
}
#endif
