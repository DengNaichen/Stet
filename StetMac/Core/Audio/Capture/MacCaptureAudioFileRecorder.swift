#if os(macOS)
    @preconcurrency import AVFoundation
    import CoreAudio
    import CoreMedia
    import Foundation
    import os
    import StetVisuals

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
        private let audioFeatureHandler: @Sendable (MacDictationCapsuleVisualSignals) -> Void
        private let audioFrameHandler: @Sendable ([Float]) -> Void
        private let onFirstRecordedBufferWritten: @Sendable () -> Void
        private let audioFeatureAnalyzer = MacDictationAudioFeatureAnalyzer()

        private var captureResources: CaptureResources?
        private var normalizedCaptureSession: MacNormalizedAudioCaptureSession?
        private var activeSession: MacAudioFileRecordingSession?
        private var stopCaptureAfterRecording = false
        private var hasWrittenFirstRecordedBuffer = false
        private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet", category: "AudioRecorder")

        nonisolated init(
            audioLevelHandler: @escaping @Sendable (Double) -> Void = { _ in },
            audioFeatureHandler: @escaping @Sendable (MacDictationCapsuleVisualSignals) -> Void = { _ in },
            audioFrameHandler: @escaping @Sendable ([Float]) -> Void = { _ in },
            onFirstRecordedBufferWritten: @escaping @Sendable () -> Void = {}
        ) {
            self.audioLevelHandler = audioLevelHandler
            self.audioFeatureHandler = audioFeatureHandler
            self.audioFrameHandler = audioFrameHandler
            self.onFirstRecordedBufferWritten = onFirstRecordedBufferWritten
            super.init()
        }

        nonisolated func startRecording(
            to fileURL: URL,
            outputFormat: AVAudioFormat,
            selectedDevice: AudioHardwareDevice?
        ) throws {
            precondition(currentSession() == nil, "MacCaptureAudioFileRecorder is already recording.")

            let startedCaptureForRecording = currentNormalizedCaptureSession() == nil
            if startedCaptureForRecording {
                try startCapture(outputFormat: outputFormat, selectedDevice: selectedDevice)
            }

            do {
                let recordingFile = try AVAudioFile(
                    forWriting: fileURL,
                    settings: outputFormat.settings,
                    commonFormat: outputFormat.commonFormat,
                    interleaved: outputFormat.isInterleaved
                )
                setCurrentSession(
                    MacAudioFileRecordingSession(
                        recordingFile: recordingFile,
                        outputFormat: outputFormat,
                        voiceProcessingEnabled: false,
                        voiceProcessingFallbackReason: "input-only avcapture capture"
                    )
                )
                setStopCaptureAfterRecording(startedCaptureForRecording)
            } catch {
                if startedCaptureForRecording {
                    stopCapture()
                }
                throw error
            }

            firstBufferLock.withLock {
                hasWrittenFirstRecordedBuffer = false
            }
        }

        nonisolated func startCapture(
            outputFormat: AVAudioFormat,
            selectedDevice: AudioHardwareDevice?
        ) throws {
            guard currentNormalizedCaptureSession() == nil else { return }

            let candidates = MacCaptureAudioDevicePlanner.inputDeviceCandidates(selectedDevice: selectedDevice)
            Self.logStartupTiming(
                "captureRecorderStart candidates=\(candidates.map { Self.describe(candidate: $0) }.joined(separator: ","))"
            )
            var startupError: Error?

            for candidate in candidates {
                let attemptStartedAt = ProcessInfo.processInfo.systemUptime
                do {
                    try startCaptureAttempt(
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
                        logger.info(
                            "macOS capture recovered using AVCapture fallback input device strategy. reason=\(candidate.reason.rawValue), device=\(candidate.device?.name ?? "systemDefault")"
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
                    logger.warning(
                        "macOS AVCapture attempt failed. reason=\(candidate.reason.rawValue), device=\(candidate.device?.name ?? "systemDefault"), error=\(error.localizedDescription)"
                    )
                    stopCapture()
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }

            if let startupError {
                logger.error(
                    "All macOS AVCapture input device candidates failed. error=\(startupError.localizedDescription)"
                )
            }

            throw SpeechServiceError.failedToStart
        }

        nonisolated func activateRecordingWindow() throws {
            try currentSession()?.activateRecordingWindow()
        }

        nonisolated func stopRecording(writtenFileAt fileURL: URL) async -> MacAudioFileRecordingOutcome {
            let outcome = finishRecordingSession()
            if shouldStopCaptureAfterRecording() {
                stopCapture()
            }
            if outcome.didWriteAudio {
                await MacRecordingFileStabilizer.waitForFileToStabilize(at: fileURL)
            }
            return outcome
        }

        nonisolated func cancelRecording() {
            _ = finishRecordingSession()
            if shouldStopCaptureAfterRecording() {
                stopCapture()
            }
        }

        nonisolated func stopCapture() {
            _ = finishRecordingSession()
            clearNormalizedCaptureSession()?.close()
            tearDownCaptureSession()
            setStopCaptureAfterRecording(false)
        }

        nonisolated func prewarm() {
            _ = MacCaptureAudioDevicePlanner.availableCaptureDevices()
        }

        deinit {
            stopCapture()
        }

        nonisolated private func startCaptureAttempt(
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

            let normalizedSession = MacNormalizedAudioCaptureSession(outputFormat: outputFormat)
            setNormalizedCaptureSession(normalizedSession)
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
                        sessionStartMs=\(Self.formatMilliseconds(sessionStartMs))
                    """
                )
            } catch {
                stopCapture()
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
                    logger.info(
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
                        """
                    )
                    break
                }

                Self.logStartupTiming(
                    "captureRecorderSessionStartFailed attempt=\(attempt) attemptMs=\(Self.formatMilliseconds(attemptMs))"
                )
                logger.warning(
                    "macOS AVCapture session start failed on attempt \(attempt). Retrying..."
                )
                Thread.sleep(forTimeInterval: Configuration.startupRetryDelaySeconds)
            }

            guard didStart else {
                logger.error(
                    "Failed to start the macOS AVCapture session after retries. captureDevice=\(resources.device.localizedName)"
                )
                throw CaptureError.failedToStartSession(device: resources.device.localizedName)
            }
        }

        nonisolated private func handleIncomingSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
            guard let captureSession = currentNormalizedCaptureSession() else {
                return
            }

            guard CMSampleBufferDataIsReady(sampleBuffer) else {
                return
            }

            do {
                let inputBuffer = try MacCaptureAudioSampleBufferConverter.pcmBuffer(from: sampleBuffer)
                audioLevelHandler(AudioLevelNormalizer.normalizedLevel(from: inputBuffer))
                if let audioFeatureAnalyzer {
                    audioFeatureHandler(audioFeatureAnalyzer.analyze(buffer: inputBuffer))
                }

                let conversion = try captureSession.convert(inputBuffer)
                if conversion.didCreateConverter {
                    logger.info(
                        """
                        Prepared mac transcription converter from AVCapture audio buffer. \
                        actualInputSampleRate=\(Int(inputBuffer.format.sampleRate)), \
                        actualInputChannels=\(inputBuffer.format.channelCount), \
                        actualInputCommonFormat=\(String(describing: inputBuffer.format.commonFormat)), \
                        actualInputInterleaved=\(inputBuffer.format.isInterleaved)
                        """
                    )
                }

                let convertedBuffer = conversion.buffer
                guard convertedBuffer.frameLength > 0 else {
                    return
                }

                audioFrameHandler(MacNormalizedAudioSamples.samples(from: convertedBuffer))

                guard let session = currentSession(),
                    let ingestionResult = try session.ingestConvertedBuffer(convertedBuffer)
                else {
                    return
                }

                emitFirstRecordedBufferIfNeeded(didWriteAudioFrames: ingestionResult.didWriteAudioFrames)
            } catch {
                guard currentSession()?.shouldLogDroppedBuffer() ?? true else {
                    return
                }

                logger.warning(
                    "Dropping AVCapture audio buffer before transcription write. error=\(error.localizedDescription)"
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

        nonisolated private func finishRecordingSession() -> MacAudioFileRecordingOutcome {
            let session = clearCurrentSession()
            let outcome = session?.recordingOutcome() ?? .empty
            session?.close()

            firstBufferLock.withLock {
                hasWrittenFirstRecordedBuffer = false
            }

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

        nonisolated private func currentNormalizedCaptureSession() -> MacNormalizedAudioCaptureSession? {
            stateLock.withLock { normalizedCaptureSession }
        }

        nonisolated private func setNormalizedCaptureSession(_ session: MacNormalizedAudioCaptureSession) {
            stateLock.withLock { normalizedCaptureSession = session }
        }

        nonisolated private func clearNormalizedCaptureSession() -> MacNormalizedAudioCaptureSession? {
            stateLock.withLock {
                defer { normalizedCaptureSession = nil }
                return normalizedCaptureSession
            }
        }

        nonisolated private func setStopCaptureAfterRecording(_ value: Bool) {
            stateLock.withLock { stopCaptureAfterRecording = value }
        }

        nonisolated private func shouldStopCaptureAfterRecording() -> Bool {
            stateLock.withLock { stopCaptureAfterRecording }
        }

        private nonisolated static func describe(candidate: InputDeviceCandidate) -> String {
            "\(candidate.reason.rawValue):\(candidate.device?.name ?? "systemDefault")"
        }

        private nonisolated static func logStartupTiming(_ payload: String) {
            guard UserDefaults.standard.bool(forKey: MacPreferences.dictationPerfTracingEnabled) else {
                return
            }

            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet", category: "AudioStartup").info(
                "AudioStartup \(payload)")
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
