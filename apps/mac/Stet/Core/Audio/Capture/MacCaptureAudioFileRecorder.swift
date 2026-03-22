#if os(macOS)
@preconcurrency import AVFoundation
import CoreAudio
import CoreMedia
import Foundation

nonisolated final class MacCaptureAudioFileRecorder: NSObject, @unchecked Sendable {
    private enum Configuration {
        nonisolated static let startupRetryCount = 4
        nonisolated static let startupRetryDelaySeconds = 0.15
    }

    private let firstBufferLock = NSLock()
    private let stateLock = NSLock()
    private let captureQueue = DispatchQueue(
        label: "Stet.MacCaptureAudioFileRecorder.capture",
        qos: .userInitiated
    )
    private let audioLevelHandler: @Sendable (Double) -> Void
    private let onFirstRecordedBufferWritten: @Sendable () -> Void

    private var captureResources: CaptureResources?
    private var activeSession: MacAudioFileRecordingSession?
    private var hasWrittenFirstRecordedBuffer = false

    nonisolated init(
        audioLevelHandler: @escaping @Sendable (Double) -> Void = { _ in },
        onFirstRecordedBufferWritten: @escaping @Sendable () -> Void = {}
    ) {
        self.audioLevelHandler = audioLevelHandler
        self.onFirstRecordedBufferWritten = onFirstRecordedBufferWritten
        super.init()
    }

    nonisolated func startRecording(
        to fileURL: URL,
        outputFormat: AVAudioFormat,
        selectedDevice: AudioHardwareDevice?
    ) throws {
        precondition(currentSession() == nil, "MacCaptureAudioFileRecorder is already recording.")

        let candidates = MacCaptureAudioDevicePlanner.inputDeviceCandidates(selectedDevice: selectedDevice)
        Self.logStartupTiming(
            "captureRecorderStart candidates=\(candidates.map { Self.describe(candidate: $0) }.joined(separator: ","))"
        )
        var startupError: Error?

        for candidate in candidates {
            let attemptStartedAt = ProcessInfo.processInfo.systemUptime
            do {
                try startRecordingAttempt(
                    to: fileURL,
                    outputFormat: outputFormat,
                    inputDevice: candidate.device,
                    candidateReason: candidate.reason
                )
                let attemptMs = Self.elapsedMilliseconds(since: attemptStartedAt)
                Self.logStartupTiming(
                    """
                    captureRecorderCandidateSuccess reason=\(candidate.reason.rawValue) \
                    device=\(candidate.device?.name ?? "systemDefault") \
                    attemptMs=\(Self.formatMilliseconds(attemptMs))
                    """
                )
                if candidate.reason != .selected {
                    AppLogger.info(
                        "macOS capture recovered using AVCapture fallback input device strategy. reason=\(candidate.reason.rawValue), device=\(candidate.device?.name ?? "systemDefault")",
                        category: .dictation
                    )
                }
                return
            } catch {
                startupError = error
                let attemptMs = Self.elapsedMilliseconds(since: attemptStartedAt)
                Self.logStartupTiming(
                    """
                    captureRecorderCandidateFailed reason=\(candidate.reason.rawValue) \
                    device=\(candidate.device?.name ?? "systemDefault") \
                    attemptMs=\(Self.formatMilliseconds(attemptMs)) \
                    error=\(error.localizedDescription)
                    """
                )
                AppLogger.warning(
                    "macOS AVCapture attempt failed. reason=\(candidate.reason.rawValue), device=\(candidate.device?.name ?? "systemDefault"), error=\(error.localizedDescription)",
                    category: .dictation
                )
                _ = finishSession()
                Thread.sleep(forTimeInterval: 0.1)
            }
        }

        if let startupError {
            AppLogger.error(
                "All macOS AVCapture input device candidates failed. error=\(startupError.localizedDescription)",
                category: .dictation
            )
        }

        throw SpeechServiceError.failedToStart
    }

    nonisolated func activateRecordingWindow() throws {
        try currentSession()?.activateRecordingWindow()
    }

    nonisolated func stopRecording(writtenFileAt fileURL: URL) async -> MacAudioFileRecordingOutcome {
        let outcome = finishSession()
        if outcome.didWriteAudio {
            await MacRecordingFileStabilizer.waitForFileToStabilize(at: fileURL)
        }
        return outcome
    }

    nonisolated func cancelRecording() {
        _ = finishSession()
    }

    nonisolated func prewarm() {
        _ = MacCaptureAudioDevicePlanner.availableCaptureDevices()
    }

    deinit {
        _ = finishSession()
    }

    nonisolated private func startRecordingAttempt(
        to fileURL: URL,
        outputFormat: AVAudioFormat,
        inputDevice: AudioHardwareDevice?,
        candidateReason: InputDeviceCandidate.Reason
    ) throws {
        let captureDeviceStartedAt = ProcessInfo.processInfo.systemUptime
        let captureDevice = try MacCaptureAudioDevicePlanner.resolveCaptureDevice(for: inputDevice)
        let captureDeviceMs = Self.elapsedMilliseconds(since: captureDeviceStartedAt)

        let resources = try MacCaptureAudioSessionFactory.makeCaptureResources(
            for: captureDevice,
            delegate: self,
            queue: captureQueue
        )

        let recordingFileStartedAt = ProcessInfo.processInfo.systemUptime
        let recordingFile = try AVAudioFile(
            forWriting: fileURL,
            settings: outputFormat.settings,
            commonFormat: outputFormat.commonFormat,
            interleaved: outputFormat.isInterleaved
        )
        let recordingFileMs = Self.elapsedMilliseconds(since: recordingFileStartedAt)

        let recordingSession = MacAudioFileRecordingSession(
            recordingFile: recordingFile,
            outputFormat: outputFormat,
            voiceProcessingEnabled: false,
            voiceProcessingFallbackReason: "input-only avcapture capture"
        )

        firstBufferLock.lock()
        hasWrittenFirstRecordedBuffer = false
        firstBufferLock.unlock()

        setCurrentSession(recordingSession)
        setCaptureResources(resources)

        do {
            let sessionStartStartedAt = ProcessInfo.processInfo.systemUptime
            try startCaptureSession(
                resources,
                inputDevice: inputDevice,
                outputFormat: outputFormat
            )
            let sessionStartMs = Self.elapsedMilliseconds(since: sessionStartStartedAt)
            Self.logStartupTiming(
                """
                captureRecorderAttempt reason=\(candidateReason.rawValue) \
                device=\(inputDevice?.name ?? "systemDefault") \
                captureDeviceName=\(captureDevice.localizedName) \
                captureDeviceMs=\(Self.formatMilliseconds(captureDeviceMs)) \
                recordingFileMs=\(Self.formatMilliseconds(recordingFileMs)) \
                sessionStartMs=\(Self.formatMilliseconds(sessionStartMs))
                """
            )
        } catch {
            _ = finishSession()
            throw error
        }
    }

    nonisolated private func startCaptureSession(
        _ resources: CaptureResources,
        inputDevice: AudioHardwareDevice?,
        outputFormat: AVAudioFormat
    ) throws {
        var didStart = false

        for attempt in 1...Configuration.startupRetryCount {
            let attemptStartedAt = ProcessInfo.processInfo.systemUptime
            captureQueue.sync {
                if !resources.session.isRunning {
                    resources.session.startRunning()
                }
            }
            let attemptMs = Self.elapsedMilliseconds(since: attemptStartedAt)

            if resources.session.isRunning {
                didStart = true
                Self.logStartupTiming(
                    "captureRecorderSessionStartSuccess attempt=\(attempt) attemptMs=\(Self.formatMilliseconds(attemptMs))"
                )

                let outputDevice = AudioInputDeviceManager.defaultOutputDevice()
                AppLogger.info(
                    """
                    Configured mac transcription AVCapture session. \
                    inputDevice=\(inputDevice?.name ?? "unknown"), \
                    inputTransport=\(inputDevice?.transportType ?? 0), \
                    captureDevice=\(resources.device.localizedName), \
                    captureUniqueID=\(resources.device.uniqueID), \
                    outputDevice=\(outputDevice?.name ?? "unknown"), \
                    outputTransport=\(outputDevice?.transportType ?? 0), \
                    fileSampleRate=\(Int(outputFormat.sampleRate)), \
                    fileChannels=\(outputFormat.channelCount), \
                    fileInterleaved=\(outputFormat.isInterleaved)
                    """,
                    category: .dictation
                )
                break
            }

            Self.logStartupTiming(
                "captureRecorderSessionStartFailed attempt=\(attempt) attemptMs=\(Self.formatMilliseconds(attemptMs))"
            )
            AppLogger.warning(
                "macOS AVCapture session start failed on attempt \(attempt). Retrying...",
                category: .dictation
            )
            Thread.sleep(forTimeInterval: Configuration.startupRetryDelaySeconds)
        }

        guard didStart else {
            AppLogger.error(
                "Failed to start the macOS AVCapture session after retries. captureDevice=\(resources.device.localizedName)",
                category: .dictation
            )
            throw CaptureError.failedToStartSession(device: resources.device.localizedName)
        }
    }

    nonisolated private func handleIncomingSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let session = currentSession() else {
            return
        }

        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        do {
            let inputBuffer = try MacCaptureAudioSampleBufferConverter.pcmBuffer(from: sampleBuffer)
            audioLevelHandler(AudioLevelNormalizer.normalizedLevel(from: inputBuffer))

            guard let snapshot = try session.snapshot(for: inputBuffer.format) else {
                return
            }

            if snapshot.didCreateConverter {
                AppLogger.info(
                    """
                    Prepared mac transcription converter from AVCapture audio buffer. \
                    actualInputSampleRate=\(Int(inputBuffer.format.sampleRate)), \
                    actualInputChannels=\(inputBuffer.format.channelCount), \
                    actualInputCommonFormat=\(String(describing: inputBuffer.format.commonFormat)), \
                    actualInputInterleaved=\(inputBuffer.format.isInterleaved)
                    """,
                    category: .dictation
                )
            }

            let convertedBuffer = try LinearPCMConversion.convert(
                inputBuffer,
                using: snapshot.converter,
                outputFormat: session.outputFormat
            )
            guard convertedBuffer.frameLength > 0 else {
                return
            }

            guard let ingestionResult = try session.ingestConvertedBuffer(convertedBuffer) else {
                return
            }

            emitFirstRecordedBufferIfNeeded(didWriteAudioFrames: ingestionResult.didWriteAudioFrames)
        } catch {
            guard session.shouldLogDroppedBuffer() else {
                return
            }

            AppLogger.warning(
                "Dropping AVCapture audio buffer before transcription write. error=\(error.localizedDescription)",
                category: .dictation
            )
        }
    }

    nonisolated private func emitFirstRecordedBufferIfNeeded(didWriteAudioFrames: Bool) {
        guard didWriteAudioFrames else { return }

        firstBufferLock.lock()
        let shouldEmit = !hasWrittenFirstRecordedBuffer
        if shouldEmit {
            hasWrittenFirstRecordedBuffer = true
        }
        firstBufferLock.unlock()

        if shouldEmit {
            onFirstRecordedBufferWritten()
        }
    }

    nonisolated private func finishSession() -> MacAudioFileRecordingOutcome {
        let session = clearCurrentSession()
        let outcome = session?.recordingOutcome() ?? .empty
        session?.close()
        tearDownCaptureSession()

        firstBufferLock.lock()
        hasWrittenFirstRecordedBuffer = false
        firstBufferLock.unlock()

        return outcome
    }

    nonisolated private func tearDownCaptureSession() {
        guard let resources = clearCaptureResources() else {
            return
        }

        resources.output.setSampleBufferDelegate(nil, queue: nil)
        captureQueue.sync {
            if resources.session.isRunning {
                resources.session.stopRunning()
            }
        }
    }

    nonisolated private func currentSession() -> MacAudioFileRecordingSession? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeSession
    }

    nonisolated private func setCurrentSession(_ session: MacAudioFileRecordingSession) {
        stateLock.lock()
        activeSession = session
        stateLock.unlock()
    }

    nonisolated private func clearCurrentSession() -> MacAudioFileRecordingSession? {
        stateLock.lock()
        let session = activeSession
        activeSession = nil
        stateLock.unlock()
        return session
    }

    nonisolated private func setCaptureResources(_ resources: CaptureResources) {
        stateLock.lock()
        captureResources = resources
        stateLock.unlock()
    }

    nonisolated private func clearCaptureResources() -> CaptureResources? {
        stateLock.lock()
        let resources = captureResources
        captureResources = nil
        stateLock.unlock()
        return resources
    }

    private nonisolated static func describe(candidate: InputDeviceCandidate) -> String {
        "\(candidate.reason.rawValue):\(candidate.device?.name ?? "systemDefault")"
    }

    private nonisolated static func logStartupTiming(_ payload: String) {
        guard UserDefaults.standard.bool(forKey: MacPreferences.dictationPerfTracingEnabled) else {
            return
        }

        AppLogger.info("AudioStartup \(payload)", category: .perfTrace)
    }

    private nonisolated static func elapsedMilliseconds(since start: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1_000
    }

    private nonisolated static func formatMilliseconds(_ duration: Double) -> String {
        String(format: "%.1f", duration)
    }
}

extension MacCaptureAudioFileRecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        _ = output
        _ = connection
        handleIncomingSampleBuffer(sampleBuffer)
    }
}
#endif
