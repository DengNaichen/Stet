#if os(macOS)
@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

struct MacAudioFileRecordingOutcome: Sendable {
    let writtenFrameCount: AVAudioFramePosition
    let didWriteAudio: Bool
    let captureBackend: String?
    let captureDiagnosticsSummary: String?

    static let empty = Self(
        writtenFrameCount: 0,
        didWriteAudio: false,
        captureBackend: nil,
        captureDiagnosticsSummary: nil
    )
}

final class MacAudioFileRecordingSession {
    struct BufferIngestionResult: Sendable {
        let didWriteAudioFrames: Bool
    }

    private enum Configuration {
        static let pendingAudioLimitSeconds: Double = 1.5
    }

    private let lock = NSLock()
    let outputFormat: AVAudioFormat
    private let captureBackend: String
    private let voiceProcessingEnabled: Bool
    private let voiceProcessingFallbackReason: String?
    private var converter: AVAudioConverter?
    private var converterInputFormatSignature: String?
    private var recordingFile: AVAudioFile?
    private var writtenFrameCount: AVAudioFramePosition = 0
    private var didWriteAudio = false
    private var droppedBufferLogCount = 0
    private var hasActivatedCaptureWindow = false
    private var pendingBuffers: [AVAudioPCMBuffer] = []
    private var pendingFrameCount: AVAudioFramePosition = 0

    init(
        recordingFile: AVAudioFile,
        outputFormat: AVAudioFormat,
        captureBackend: String = "unknown",
        voiceProcessingEnabled: Bool,
        voiceProcessingFallbackReason: String?
    ) {
        self.recordingFile = recordingFile
        self.outputFormat = outputFormat
        self.captureBackend = captureBackend
        self.voiceProcessingEnabled = voiceProcessingEnabled
        self.voiceProcessingFallbackReason = voiceProcessingFallbackReason
    }

    func snapshot(
        for inputFormat: AVAudioFormat
    ) throws -> (converter: AVAudioConverter, recordingFile: AVAudioFile, didCreateConverter: Bool)? {
        lock.lock()
        defer { lock.unlock() }

        guard let recordingFile else {
            return nil
        }

        let inputFormatSignature = Self.formatSignature(inputFormat)
        let didCreateConverter: Bool

        if converterInputFormatSignature != inputFormatSignature || converter == nil {
            guard let converter = LinearPCMConversion.makeConverter(
                from: inputFormat,
                to: outputFormat
            ) else {
                throw LinearPCMConversion.ConversionError.conversionFailed
            }

            self.converter = converter
            self.converterInputFormatSignature = inputFormatSignature
            didCreateConverter = true
        } else {
            didCreateConverter = false
        }

        guard let converter else {
            throw LinearPCMConversion.ConversionError.conversionFailed
        }

        return (converter, recordingFile, didCreateConverter)
    }

    func ingestConvertedBuffer(_ buffer: AVAudioPCMBuffer) throws -> BufferIngestionResult? {
        lock.lock()
        defer { lock.unlock() }

        guard let recordingFile else {
            return nil
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return BufferIngestionResult(didWriteAudioFrames: false)
        }

        guard hasActivatedCaptureWindow else {
            appendPendingBuffer(buffer)
            return BufferIngestionResult(didWriteAudioFrames: false)
        }

        try writeLocked(buffer, to: recordingFile)

        return BufferIngestionResult(didWriteAudioFrames: true)
    }

    func shouldLogDroppedBuffer() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard droppedBufferLogCount < 3 else {
            return false
        }

        droppedBufferLogCount += 1
        return true
    }

    func activateRecordingWindow() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !hasActivatedCaptureWindow else {
            return
        }

        hasActivatedCaptureWindow = true
        guard let recordingFile else {
            pendingBuffers.removeAll(keepingCapacity: false)
            pendingFrameCount = 0
            return
        }

        for buffer in pendingBuffers {
            try writeLocked(buffer, to: recordingFile)
        }
        pendingBuffers.removeAll(keepingCapacity: false)
        pendingFrameCount = 0
    }

    func close() {
        lock.lock()
        converter = nil
        converterInputFormatSignature = nil
        recordingFile = nil
        lock.unlock()
    }

    func recordingOutcome() -> MacAudioFileRecordingOutcome {
        lock.lock()
        defer { lock.unlock() }

        let diagnostics =
            """
            didWriteAudio=\(didWriteAudio) activated=\(hasActivatedCaptureWindow) \
            captureBackend=\(captureBackend) \
            writtenFrames=\(writtenFrameCount) pendingFrames=\(pendingFrameCount) \
            voiceProcessingEnabled=\(voiceProcessingEnabled) \
            fallbackReason=\(voiceProcessingFallbackReason ?? "none")
            """

        return MacAudioFileRecordingOutcome(
            writtenFrameCount: writtenFrameCount,
            didWriteAudio: didWriteAudio,
            captureBackend: captureBackend,
            captureDiagnosticsSummary: diagnostics
        )
    }

    private static func formatSignature(_ format: AVAudioFormat) -> String {
        "\(String(describing: format.commonFormat)):\(Int(format.sampleRate)):\(format.channelCount):\(format.isInterleaved)"
    }

    private func appendPendingBuffer(_ buffer: AVAudioPCMBuffer) {
        pendingBuffers.append(buffer)
        pendingFrameCount += AVAudioFramePosition(buffer.frameLength)

        let maximumBufferedFrames = AVAudioFramePosition(
            max(outputFormat.sampleRate * Configuration.pendingAudioLimitSeconds, 0)
        )

        guard maximumBufferedFrames > 0 else {
            pendingBuffers.removeAll(keepingCapacity: false)
            pendingFrameCount = 0
            return
        }

        while pendingFrameCount > maximumBufferedFrames, let oldestBuffer = pendingBuffers.first {
            pendingBuffers.removeFirst()
            pendingFrameCount -= AVAudioFramePosition(oldestBuffer.frameLength)
        }
    }

    private func writeLocked(_ buffer: AVAudioPCMBuffer, to recordingFile: AVAudioFile) throws {
        try recordingFile.write(from: buffer)
        writtenFrameCount += AVAudioFramePosition(buffer.frameLength)
        didWriteAudio = true
    }
}

final class MacAudioFileRecorder: @unchecked Sendable {
    struct VoiceProcessingConfigurationResult: Sendable {
        let enabled: Bool
        let fallbackReason: String?
    }

    private enum Configuration {
        static let tapBufferSize: AVAudioFrameCount = 256
    }

    private let firstBufferLock = NSLock()
    private let capturedAudioLock = NSLock()
    private let stateLock = NSLock()
    private let audioLevelHandler: @Sendable (Double) -> Void
    private let onFirstRecordedBufferWritten: @Sendable () -> Void
    private let configureVoiceProcessing: @Sendable (
        AVAudioInputNode,
        AVAudioOutputNode?,
        AudioHardwareDevice?,
        MacCaptureAttemptPlan
    ) -> VoiceProcessingConfigurationResult

    private var audioEngine: AVAudioEngine?
    private var activeSession: MacAudioFileRecordingSession?
    private var hasWrittenFirstRecordedBuffer = false
    private var hasCapturedAudio = false

    convenience init(
        audioLevelHandler: @escaping @Sendable (Double) -> Void = { _ in },
        onFirstRecordedBufferWritten: @escaping @Sendable () -> Void = {}
    ) {
        self.init(
            audioLevelHandler: audioLevelHandler,
            onFirstRecordedBufferWritten: onFirstRecordedBufferWritten,
            configureVoiceProcessing: { inputNode, outputNode, inputDevice, attempt in
                Self.configureVoiceProcessing(
                    inputNode: inputNode,
                    outputNode: outputNode,
                    inputDevice: inputDevice,
                    attempt: attempt
                )
            }
        )
    }

    init(
        audioLevelHandler: @escaping @Sendable (Double) -> Void,
        onFirstRecordedBufferWritten: @escaping @Sendable () -> Void,
        configureVoiceProcessing: @escaping @Sendable (
            AVAudioInputNode,
            AVAudioOutputNode?,
            AudioHardwareDevice?,
            MacCaptureAttemptPlan
        ) -> VoiceProcessingConfigurationResult
    ) {
        self.audioLevelHandler = audioLevelHandler
        self.onFirstRecordedBufferWritten = onFirstRecordedBufferWritten
        self.configureVoiceProcessing = configureVoiceProcessing
    }

    nonisolated func startRecordingAttempt(
        to fileURL: URL,
        outputFormat: AVAudioFormat,
        attempt: MacCaptureAttemptPlan
    ) throws {
        precondition(currentSession() == nil, "MacAudioFileRecorder is already recording.")
        try startRecordingAttempt(
            to: fileURL,
            outputFormat: outputFormat,
            inputDevice: attempt.inputDevice,
            attempt: attempt
        )
    }

    nonisolated func activateRecordingWindow() throws {
        try currentSession()?.activateRecordingWindow()
    }

    nonisolated func stopRecording(writtenFileAt fileURL: URL) async -> MacAudioFileRecordingOutcome {
        let outcome = finishSession()
        if outcome.didWriteAudio {
            await Self.waitForFileToStabilize(at: fileURL)
        }
        return outcome
    }

    nonisolated func cancelRecording() {
        _ = finishSession()
    }

    nonisolated func waitForCapturedAudio(timeout: Duration) async -> Bool {
        if didCaptureAudio() {
            return true
        }

        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if didCaptureAudio() {
                return true
            }

            try? await Task.sleep(for: .milliseconds(20))
        }

        return didCaptureAudio()
    }

    nonisolated func prewarm() {
        let engine = ensurePrewarmedEngine()
        _ = engine.inputNode
        engine.prepare()
    }

    deinit {
        _ = finishSession()
    }

    nonisolated private func startRecordingSession(
        _ recordingSession: MacAudioFileRecordingSession,
        on inputNode: AVAudioInputNode,
        outputFormat: AVAudioFormat,
        voiceProcessing: VoiceProcessingConfigurationResult,
        inputDevice: AudioHardwareDevice?
    ) throws {
        let tapFormat = inputNode.outputFormat(forBus: 0)
        _ = try recordingSession.snapshot(for: tapFormat)
        setCurrentSession(recordingSession)

        try startEngine(on: inputNode, tapFormat: tapFormat)

        let outputDevice = AudioInputDeviceManager.defaultOutputDevice()
        AppLogger.info(
            """
            Configuring mac transcription capture. \
            inputDevice=\(inputDevice?.name ?? "unknown"), \
            inputTransport=\(inputDevice?.transportType ?? 0), \
            outputDevice=\(outputDevice?.name ?? "unknown"), \
            outputTransport=\(outputDevice?.transportType ?? 0), \
            voiceProcessingEnabled=\(voiceProcessing.enabled), \
            voiceProcessingFallbackReason=\(voiceProcessing.fallbackReason ?? "none"), \
            reportedInputSampleRate=\(Int(tapFormat.sampleRate)), \
            reportedInputChannels=\(tapFormat.channelCount), \
            tapBufferSize=\(Configuration.tapBufferSize), \
            outputSampleRate=\(Int(outputFormat.sampleRate)), \
            outputChannels=\(outputFormat.channelCount), \
            fileSampleRate=\(Int(recordingSession.outputFormat.sampleRate)), \
            fileChannels=\(recordingSession.outputFormat.channelCount), \
            fileInterleaved=\(recordingSession.outputFormat.isInterleaved)
            """,
            category: .dictation
        )
    }

    nonisolated private func startRecordingAttempt(
        to fileURL: URL,
        outputFormat: AVAudioFormat,
        inputDevice: AudioHardwareDevice?,
        attempt: MacCaptureAttemptPlan
    ) throws {
        let engine = takeOrCreateEngine()

        let inputNode = engine.inputNode
        let deviceBindingStartedAt = ProcessInfo.processInfo.systemUptime
        if let inputDevice, attempt.explicitBinding {
            try Self.bindInputDevice(inputDevice, to: inputNode)
        }
        let deviceBindingMs = Self.elapsedMilliseconds(since: deviceBindingStartedAt)

        let voiceProcessingStartedAt = ProcessInfo.processInfo.systemUptime
        let outputNode = engine.outputNode
        let voiceProcessing = configureVoiceProcessing(inputNode, outputNode, inputDevice, attempt)
        let voiceProcessingMs = Self.elapsedMilliseconds(since: voiceProcessingStartedAt)
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
            captureBackend: attempt.backend.rawValue,
            voiceProcessingEnabled: voiceProcessing.enabled,
            voiceProcessingFallbackReason: voiceProcessing.fallbackReason
        )
        resetCapturedAudio()
        firstBufferLock.lock()
        hasWrittenFirstRecordedBuffer = false
        firstBufferLock.unlock()

        do {
            let sessionStartStartedAt = ProcessInfo.processInfo.systemUptime
            try startRecordingSession(
                recordingSession,
                on: inputNode,
                outputFormat: outputFormat,
                voiceProcessing: voiceProcessing,
                inputDevice: inputDevice
            )
            let sessionStartMs = Self.elapsedMilliseconds(since: sessionStartStartedAt)
            Self.logStartupTiming(
                """
                recorderAttempt reason=\(attempt.candidate.reason.rawValue) \
                backend=\(attempt.backend.rawValue) \
                device=\(inputDevice?.name ?? "systemDefault") \
                explicitBind=\(attempt.explicitBinding) \
                deviceBindingMs=\(Self.formatMilliseconds(deviceBindingMs)) \
                voiceProcessingMs=\(Self.formatMilliseconds(voiceProcessingMs)) \
                recordingFileMs=\(Self.formatMilliseconds(recordingFileMs)) \
                sessionStartMs=\(Self.formatMilliseconds(sessionStartMs)) \
                voiceProcessingEnabled=\(voiceProcessing.enabled) \
                fallbackReason=\(voiceProcessing.fallbackReason ?? "none")
                """
            )
        } catch {
            _ = finishSession()
            throw error
        }
    }

    nonisolated private func startEngine(
        on inputNode: AVAudioInputNode,
        tapFormat: AVAudioFormat
    ) throws {
        installTap(on: inputNode, format: tapFormat)
        
        guard let engine = currentEngine() else {
            throw SpeechServiceError.failedToStart
        }
        
        engine.prepare()

        var startupError: Error?
        var didStart = false

        for attempt in 1...4 {
            let attemptStartedAt = ProcessInfo.processInfo.systemUptime
            do {
                if !engine.isRunning {
                    try engine.start()
                }
                let attemptMs = Self.elapsedMilliseconds(since: attemptStartedAt)
                startupError = nil
                didStart = true
                Self.logStartupTiming(
                    "recorderEngineStartSuccess attempt=\(attempt) attemptMs=\(Self.formatMilliseconds(attemptMs))"
                )
                if attempt > 1 {
                    AppLogger.info("macOS capture engine started successfully on attempt \(attempt).", category: .dictation)
                }
                break
            } catch {
                let attemptMs = Self.elapsedMilliseconds(since: attemptStartedAt)
                startupError = error
                Self.logStartupTiming(
                    """
                    recorderEngineStartFailed attempt=\(attempt) \
                    attemptMs=\(Self.formatMilliseconds(attemptMs)) \
                    error=\(error.localizedDescription)
                    """
                )
                AppLogger.warning(
                    "macOS capture engine start failed on attempt \(attempt). Retrying... error=\(error.localizedDescription)",
                    category: .dictation
                )
                // Allow `coreaudiod` time to drop the IO graph hardware lock from the previous session
                Thread.sleep(forTimeInterval: 0.15)
                engine.prepare()
            }
        }

        guard didStart else {
            tearDownEngine()
            if let error = startupError {
                AppLogger.error(
                    "Failed to start the macOS capture engine after retries. error=\(error.localizedDescription)",
                    category: .dictation
                )
            }
            throw SpeechServiceError.failedToStart
        }
    }

    nonisolated private func installTap(on inputNode: AVAudioInputNode, format tapFormat: AVAudioFormat) {
        inputNode.installTap(onBus: 0, bufferSize: Configuration.tapBufferSize, format: tapFormat) { [weak self] buffer, when in
            self?.handleIncomingBuffer(buffer, when: when)
        }
    }

    nonisolated private func handleIncomingBuffer(_ buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        guard let session = currentSession() else {
            return
        }

        if buffer.frameLength > 0 {
            markCapturedAudio()
        }

        guard when.isSampleTimeValid else {
            guard session.shouldLogDroppedBuffer() else {
                return
            }

            AppLogger.warning(
                """
                Dropping captured audio buffer with invalid sample time. \
                frameLength=\(buffer.frameLength), \
                sampleTimeValid=\(when.isSampleTimeValid), \
                hostTimeValid=\(when.isHostTimeValid)
                """,
                category: .dictation
            )
            return
        }

        audioLevelHandler(AudioLevelNormalizer.normalizedLevel(from: buffer))

        do {
            guard let snapshot = try session.snapshot(for: buffer.format) else {
                return
            }

            if snapshot.didCreateConverter {
                AppLogger.info(
                    """
                    Prepared mac transcription converter from tap buffer. \
                    actualInputSampleRate=\(Int(buffer.format.sampleRate)), \
                    actualInputChannels=\(buffer.format.channelCount), \
                    actualInputCommonFormat=\(String(describing: buffer.format.commonFormat)), \
                    actualInputInterleaved=\(buffer.format.isInterleaved)
                    """,
                    category: .dictation
                )
            }

            let convertedBuffer = try LinearPCMConversion.convert(
                buffer,
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
                """
                Dropping captured audio buffer before transcription write. \
                inputSampleRate=\(Int(buffer.format.sampleRate)), \
                inputChannels=\(buffer.format.channelCount), \
                inputCommonFormat=\(String(describing: buffer.format.commonFormat)), \
                inputInterleaved=\(buffer.format.isInterleaved), \
                frameLength=\(buffer.frameLength), \
                error=\(error.localizedDescription)
                """,
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
        tearDownEngine()

        firstBufferLock.lock()
        hasWrittenFirstRecordedBuffer = false
        firstBufferLock.unlock()
        resetCapturedAudio()
        return outcome
    }

    nonisolated private func tearDownEngine() {
        let engine = currentEngine()
        engine?.inputNode.removeTap(onBus: 0)

        if engine?.isRunning == true {
            engine?.stop()
        }
        engine?.reset()
        
        stateLock.lock()
        audioEngine = nil
        stateLock.unlock()
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

    nonisolated private func currentEngine() -> AVAudioEngine? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return audioEngine
    }

    nonisolated private func takeOrCreateEngine() -> AVAudioEngine {
        stateLock.lock()
        defer { stateLock.unlock() }

        if let audioEngine {
            return audioEngine
        }

        let engine = AVAudioEngine()
        audioEngine = engine
        return engine
    }

    nonisolated private func ensurePrewarmedEngine() -> AVAudioEngine {
        stateLock.lock()
        defer { stateLock.unlock() }

        if let audioEngine {
            return audioEngine
        }

        let engine = AVAudioEngine()
        audioEngine = engine
        return engine
    }

    nonisolated private func clearCurrentSession() -> MacAudioFileRecordingSession? {
        stateLock.lock()
        let session = activeSession
        activeSession = nil
        stateLock.unlock()
        return session
    }

    nonisolated private static func configureVoiceProcessing(
        inputNode: AVAudioInputNode,
        outputNode: AVAudioOutputNode?,
        inputDevice: AudioHardwareDevice?,
        attempt: MacCaptureAttemptPlan
    ) -> VoiceProcessingConfigurationResult {
        guard attempt.voiceProcessingRequested else {
            AppLogger.info(
                """
                Using raw AVAudioEngine capture after route negotiation. \
                inputDevice=\(inputDevice?.name ?? "systemDefault") \
                reason=\(attempt.voiceProcessingFallbackReason ?? "none")
                """,
                category: .dictation
            )
            return VoiceProcessingConfigurationResult(
                enabled: false,
                fallbackReason: attempt.voiceProcessingFallbackReason
            )
        }

        do {
            try inputNode.setVoiceProcessingEnabled(true)
            do {
                try outputNode?.setVoiceProcessingEnabled(true)
            } catch {
                try? inputNode.setVoiceProcessingEnabled(false)
                try? outputNode?.setVoiceProcessingEnabled(false)
                throw error
            }
            inputNode.isVoiceProcessingBypassed = false
            AppLogger.info(
                """
                Using Apple Voice Processing for macOS dictation capture. \
                inputDevice=\(inputDevice?.name ?? "systemDefault") \
                outputNodeConfigured=\(outputNode != nil)
                """,
                category: .dictation
            )
            return VoiceProcessingConfigurationResult(
                enabled: true,
                fallbackReason: nil
            )
        } catch {
            AppLogger.warning(
                """
                Falling back to raw AVAudioEngine capture because Apple Voice Processing could not be enabled. \
                inputDevice=\(inputDevice?.name ?? "systemDefault") \
                error=\(error.localizedDescription)
                """,
                category: .dictation
            )
            return VoiceProcessingConfigurationResult(
                enabled: false,
                fallbackReason: "voice processing enable failed: \(error.localizedDescription)"
            )
        }
    }

    static func waitForFileToStabilize(at fileURL: URL) async {
        var previousFileSize: Int64?

        for _ in 0..<20 {
            let currentFileSize = recordingFileSizeBytes(at: fileURL)
            let currentDuration = recordingDurationSeconds(at: fileURL)

            if let currentDuration, currentDuration > 0 {
                return
            }

            if let currentFileSize,
               currentFileSize > 0,
               previousFileSize == currentFileSize {
                return
            }

            previousFileSize = currentFileSize
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    private static func recordingDurationSeconds(at fileURL: URL) -> TimeInterval? {
        guard let audioFile = try? AVAudioFile(forReading: fileURL) else { return nil }
        let sampleRate = audioFile.fileFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        let duration = TimeInterval(audioFile.length) / sampleRate
        guard duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    private static func recordingFileSizeBytes(at fileURL: URL) -> Int64? {
        guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = resourceValues.fileSize else {
            return nil
        }

        return Int64(fileSize)
    }

    private static func bindInputDevice(
        _ device: AudioHardwareDevice,
        to inputNode: AVAudioInputNode
    ) throws {
        guard let audioUnit = inputNode.audioUnit else {
            try inputNode.auAudioUnit.setDeviceID(device.id)
            return
        }

        var deviceID = device.id
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to bind AVAudioEngine input to device \(device.name). osstatus=\(status)"
                ]
            )
        }
    }

    private static func logStartupTiming(_ payload: String) {
        guard UserDefaults.standard.bool(forKey: MacPreferences.dictationPerfTracingEnabled) else {
            return
        }

        AppLogger.info("AudioStartup \(payload)", category: .perfTrace)
    }

    private static func elapsedMilliseconds(since start: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1_000
    }

    private static func formatMilliseconds(_ duration: Double) -> String {
        String(format: "%.1f", duration)
    }

    private func markCapturedAudio() {
        capturedAudioLock.lock()
        hasCapturedAudio = true
        capturedAudioLock.unlock()
    }

    private func didCaptureAudio() -> Bool {
        capturedAudioLock.lock()
        defer { capturedAudioLock.unlock() }
        return hasCapturedAudio
    }

    private func resetCapturedAudio() {
        capturedAudioLock.lock()
        hasCapturedAudio = false
        capturedAudioLock.unlock()
    }
}
#endif
