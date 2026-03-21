#if os(macOS)
@preconcurrency import AVFoundation
import CoreAudio
import Foundation

struct MacAudioFileRecordingOutcome: Sendable {
    let writtenFrameCount: AVAudioFramePosition
    let didWriteAudio: Bool
    let captureDiagnosticsSummary: String?

    static let empty = Self(
        writtenFrameCount: 0,
        didWriteAudio: false,
        captureDiagnosticsSummary: nil
    )
}

final class MacAudioFileRecordingSession {
    struct BufferIngestionResult: Sendable {
        let didWriteAudioFrames: Bool
    }

    private let lock = NSLock()
    let outputFormat: AVAudioFormat
    private let voiceProcessingEnabled: Bool
    private let voiceProcessingFallbackReason: String?
    private var converter: AVAudioConverter?
    private var converterInputFormatSignature: String?
    private var recordingFile: AVAudioFile?
    private var writtenFrameCount: AVAudioFramePosition = 0
    private var didWriteAudio = false
    private var droppedBufferLogCount = 0
    private var hasActivatedCaptureWindow = false

    init(
        recordingFile: AVAudioFile,
        outputFormat: AVAudioFormat,
        voiceProcessingEnabled: Bool,
        voiceProcessingFallbackReason: String?
    ) {
        self.recordingFile = recordingFile
        self.outputFormat = outputFormat
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
            return BufferIngestionResult(didWriteAudioFrames: false)
        }

        try recordingFile.write(from: buffer)
        writtenFrameCount += AVAudioFramePosition(buffer.frameLength)
        didWriteAudio = true

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

    func activateRecordingWindow() {
        lock.lock()
        hasActivatedCaptureWindow = true
        lock.unlock()
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
            writtenFrames=\(writtenFrameCount) voiceProcessingEnabled=\(voiceProcessingEnabled) \
            fallbackReason=\(voiceProcessingFallbackReason ?? "none")
            """

        return MacAudioFileRecordingOutcome(
            writtenFrameCount: writtenFrameCount,
            didWriteAudio: didWriteAudio,
            captureDiagnosticsSummary: diagnostics
        )
    }

    private static func formatSignature(_ format: AVAudioFormat) -> String {
        "\(String(describing: format.commonFormat)):\(Int(format.sampleRate)):\(format.channelCount):\(format.isInterleaved)"
    }
}

final class MacAudioFileRecorder: @unchecked Sendable {
    struct VoiceProcessingConfigurationResult: Sendable {
        let enabled: Bool
        let fallbackReason: String?
    }

    private enum Configuration {
        static let tapBufferSize: AVAudioFrameCount = 1_024
    }

    private let firstBufferLock = NSLock()
    private let stateLock = NSLock()
    private let audioLevelHandler: @Sendable (Double) -> Void
    private let onFirstRecordedBufferWritten: @Sendable () -> Void
    private let configureVoiceProcessing: @Sendable (AVAudioInputNode, AVAudioOutputNode, AudioHardwareDevice?) -> VoiceProcessingConfigurationResult

    private var audioEngine: AVAudioEngine?
    private var activeSession: MacAudioFileRecordingSession?
    private var hasWrittenFirstRecordedBuffer = false

    convenience init(
        audioLevelHandler: @escaping @Sendable (Double) -> Void = { _ in },
        onFirstRecordedBufferWritten: @escaping @Sendable () -> Void = {}
    ) {
        self.init(
            audioLevelHandler: audioLevelHandler,
            onFirstRecordedBufferWritten: onFirstRecordedBufferWritten,
            configureVoiceProcessing: { inputNode, outputNode, inputDevice in
                Self.configureVoiceProcessing(
                    inputNode: inputNode,
                    outputNode: outputNode,
                    inputDevice: inputDevice
                )
            }
        )
    }

    init(
        audioLevelHandler: @escaping @Sendable (Double) -> Void,
        onFirstRecordedBufferWritten: @escaping @Sendable () -> Void,
        configureVoiceProcessing: @escaping @Sendable (AVAudioInputNode, AVAudioOutputNode, AudioHardwareDevice?) -> VoiceProcessingConfigurationResult
    ) {
        self.audioLevelHandler = audioLevelHandler
        self.onFirstRecordedBufferWritten = onFirstRecordedBufferWritten
        self.configureVoiceProcessing = configureVoiceProcessing
    }

    nonisolated func startRecording(
        to fileURL: URL,
        outputFormat: AVAudioFormat
    ) throws {
        precondition(currentSession() == nil, "MacAudioFileRecorder is already recording.")

        let engine = AVAudioEngine()
        stateLock.lock()
        audioEngine = engine
        stateLock.unlock()

        let inputNode = engine.inputNode
        let inputDevice = AudioInputDeviceManager.defaultInputDevice()
        
        if let defaultDeviceID = inputDevice?.id {
            do {
                try inputNode.auAudioUnit.setDeviceID(defaultDeviceID)
            } catch {
                AppLogger.warning(
                    "Failed to set explicit input device ID on AVAudioEngine. error=\(error.localizedDescription)",
                    category: .dictation
                )
            }
        }
        
        let outputNode = engine.outputNode
        let voiceProcessing = configureVoiceProcessing(inputNode, outputNode, inputDevice)
        let recordingFile = try AVAudioFile(
            forWriting: fileURL,
            settings: outputFormat.settings,
            commonFormat: outputFormat.commonFormat,
            interleaved: outputFormat.isInterleaved
        )
        let recordingSession = MacAudioFileRecordingSession(
            recordingFile: recordingFile,
            outputFormat: outputFormat,
            voiceProcessingEnabled: voiceProcessing.enabled,
            voiceProcessingFallbackReason: voiceProcessing.fallbackReason
        )
        firstBufferLock.lock()
        hasWrittenFirstRecordedBuffer = false
        firstBufferLock.unlock()

        do {
            try startRecordingSession(
                recordingSession,
                on: inputNode,
                outputNode: outputNode,
                outputFormat: outputFormat,
                voiceProcessing: voiceProcessing
            )
        } catch {
            _ = finishSession()
            throw error
        }
    }

    nonisolated func activateRecordingWindow() {
        currentSession()?.activateRecordingWindow()
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

    nonisolated func prewarm() {
        _ = currentEngine()
    }

    deinit {
        _ = finishSession()
    }

    nonisolated private func startRecordingSession(
        _ recordingSession: MacAudioFileRecordingSession,
        on inputNode: AVAudioInputNode,
        outputNode: AVAudioOutputNode,
        outputFormat: AVAudioFormat,
        voiceProcessing: VoiceProcessingConfigurationResult
    ) throws {
        let tapFormat = inputNode.outputFormat(forBus: 0)
        _ = try recordingSession.snapshot(for: tapFormat)
        setCurrentSession(recordingSession)

        try startEngine(on: inputNode, tapFormat: tapFormat)

        let inputDevice = AudioInputDeviceManager.defaultInputDevice()
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
            fileInterleaved=\(recordingSession.outputFormat.isInterleaved), \
            outputNodeSampleRate=\(Int(outputNode.outputFormat(forBus: 0).sampleRate))
            """,
            category: .dictation
        )
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
            do {
                if !engine.isRunning {
                    try engine.start()
                }
                startupError = nil
                didStart = true
                if attempt > 1 {
                    AppLogger.info("macOS capture engine started successfully on attempt \(attempt).", category: .dictation)
                }
                break
            } catch {
                startupError = error
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

    nonisolated private func clearCurrentSession() -> MacAudioFileRecordingSession? {
        stateLock.lock()
        let session = activeSession
        activeSession = nil
        stateLock.unlock()
        return session
    }

    nonisolated private static func configureVoiceProcessing(
        inputNode: AVAudioInputNode,
        outputNode: AVAudioOutputNode,
        inputDevice: AudioHardwareDevice?
    ) -> VoiceProcessingConfigurationResult {
        let isBluetooth = inputDevice?.transportType == kAudioDeviceTransportTypeBluetooth ||
                          inputDevice?.transportType == kAudioDeviceTransportTypeBluetoothLE
                          
        if isBluetooth {
            try? inputNode.setVoiceProcessingEnabled(true)
            try? outputNode.setVoiceProcessingEnabled(true)
            inputNode.isVoiceProcessingBypassed = false
            AppLogger.info(
                "Using Apple Voice Processing for Bluetooth capture fidelity.",
                category: .dictation
            )
            return VoiceProcessingConfigurationResult(
                enabled: true,
                fallbackReason: "bluetooth device requires voice processing"
            )
        }

        // Keep the capture path raw for now. The built-in Voice Processing
        // path can reshape mic audio enough to hurt ASR fidelity, and the app
        // already pauses media / hides prompt audio separately.
        try? inputNode.setVoiceProcessingEnabled(false)
        try? outputNode.setVoiceProcessingEnabled(false)
        inputNode.isVoiceProcessingBypassed = true
        AppLogger.info(
            "Using raw macOS capture without Apple Voice Processing.",
            category: .dictation
        )
        return VoiceProcessingConfigurationResult(
            enabled: false,
            fallbackReason: "voice processing disabled for capture fidelity"
        )
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
}
#endif
