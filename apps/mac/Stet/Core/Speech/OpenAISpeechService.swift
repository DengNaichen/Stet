@preconcurrency import AVFoundation
import Foundation

actor OpenAISpeechService: SpeechService, AudioLevelStreaming {
    #if os(macOS)
    private final class MacRecordingResources {
        private let lock = NSLock()
        private let outputFormat: AVAudioFormat
        private var converter: AVAudioConverter?
        private var converterInputFormatSignature: String?
        private var recordingFile: AVAudioFile?
        private var writtenFrameCount: AVAudioFramePosition = 0
        private var droppedBufferLogCount = 0

        init(recordingFile: AVAudioFile, outputFormat: AVAudioFormat) {
            self.recordingFile = recordingFile
            self.outputFormat = outputFormat
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
                guard let converter = TranscriptionUploadAudioFormat.makeMacConverter(
                    from: inputFormat,
                    to: outputFormat
                ) else {
                    throw SpeechServiceError.unsupportedAudioFormat
                }

                self.converter = converter
                self.converterInputFormatSignature = inputFormatSignature
                didCreateConverter = true
            } else {
                didCreateConverter = false
            }

            guard let converter else {
                throw SpeechServiceError.unsupportedAudioFormat
            }

            return (converter, recordingFile, didCreateConverter)
        }

        func recordWrite(frameLength: AVAudioFrameCount) {
            lock.lock()
            writtenFrameCount += AVAudioFramePosition(frameLength)
            lock.unlock()
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

        func close() {
            lock.lock()
            converter = nil
            converterInputFormatSignature = nil
            recordingFile = nil
            lock.unlock()
        }

        func totalWrittenFrames() -> AVAudioFramePosition {
            lock.lock()
            defer { lock.unlock() }
            return writtenFrameCount
        }

        private static func formatSignature(_ format: AVAudioFormat) -> String {
            "\(String(describing: format.commonFormat)):\(Int(format.sampleRate)):\(format.channelCount):\(format.isInterleaved)"
        }
    }
    #endif

    private let transcriptionService: any AudioFileTranscriptionService
    private let locale: Locale
    private let transcriptionPromptProvider: (@Sendable () async -> String?)?
    #if os(macOS)
    private let audioEngine = AVAudioEngine()
    private var isTapInstalled = false
    private var macRecordingResources: MacRecordingResources?
    #endif
    private let audioLevelBridge = AudioLevelBridge()

    private var recorder: AVAudioRecorder?
    private var recordingFileURL: URL?
    private var isRecording = false
    private var meteringTask: Task<Void, Never>?

    init(
        transcriptionService: any AudioFileTranscriptionService,
        locale: Locale = .autoupdatingCurrent,
        transcriptionPromptProvider: (@Sendable () async -> String?)? = nil
    ) {
        self.transcriptionService = transcriptionService
        self.locale = locale
        self.transcriptionPromptProvider = transcriptionPromptProvider
    }

    func makeAudioLevelStream() async -> AsyncStream<Double> {
        audioLevelBridge.makeStream()
    }

    func startRecording() async throws {
        guard !isRecording else {
            throw SpeechServiceError.alreadyRecording
        }

        AppLogger.info("Starting dictation capture", category: .dictation)
        let microphoneGranted = await requestMicrophonePermission()
        guard microphoneGranted else {
            AppLogger.warning("Microphone permission denied before recording start", category: .permissions)
            throw SpeechServiceError.microphonePermissionDenied
        }

        try Task.checkCancellation()
        try configureAudioSession()

        #if os(macOS)
        try startMacRecording()
        #else
        let fileURL = makeRecordingFileURL()
        let recorder = try AVAudioRecorder(url: fileURL, settings: makeRecorderSettings())

        recorder.prepareToRecord()
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw SpeechServiceError.failedToStart
        }

        self.recorder = recorder
        self.recordingFileURL = fileURL
        self.isRecording = true
        startMetering(with: recorder)
        #endif
        AppLogger.info("Dictation capture started successfully", category: .dictation)
    }

    func stopRecording() async throws -> String {
        guard isRecording, let recordingFileURL else {
            throw SpeechServiceError.notRecording
        }

        #if os(macOS)
        let writtenFrameCount = finishInput()
        self.isRecording = false
        await Self.waitForRecordingFileToStabilize(at: recordingFileURL)
        #else
        guard let recorder else {
            throw SpeechServiceError.notRecording
        }
        recorder.stop()
        self.recorder = nil
        self.isRecording = false
        stopMetering()
        let writtenFrameCount: AVAudioFramePosition = 0
        #endif

        let audioDurationSeconds = Self.recordingDurationSeconds(at: recordingFileURL) ?? {
            #if os(macOS)
            guard writtenFrameCount > 0 else { return nil }
            return TimeInterval(writtenFrameCount) / TranscriptionUploadAudioFormat.macSampleRate
            #else
            return nil
            #endif
        }()
        let durationDescription = Self.durationDescription(audioDurationSeconds)
        let recordingFileSizeBytes = Self.recordingFileSizeBytes(at: recordingFileURL)
        AppLogger.info(
            """
            Stopping dictation capture and starting transcription. \
            durationSeconds=\(durationDescription), \
            fileSizeBytes=\(recordingFileSizeBytes.map(String.init) ?? "unknown"), \
            writtenFrames=\(writtenFrameCount)
            """,
            category: .dictation
        )

        if writtenFrameCount == 0 {
            cleanupRecordingFile()
            AppLogger.warning(
                "Skipping transcription because no audio frames were written to disk.",
                category: .dictation
            )
            throw SpeechServiceError.emptyTranscription
        }

        if let audioDurationSeconds, audioDurationSeconds < 0.1 {
            cleanupRecordingFile()
            AppLogger.warning(
                "Skipping transcription because the captured audio is too short. durationSeconds=\(durationDescription), writtenFrames=\(writtenFrameCount)",
                category: .dictation
            )
            throw SpeechServiceError.emptyTranscription
        }

        if let recordingFileSizeBytes, recordingFileSizeBytes <= 64 {
            cleanupRecordingFile()
            AppLogger.warning(
                "Skipping transcription because the captured audio file is effectively empty. fileSizeBytes=\(recordingFileSizeBytes), writtenFrames=\(writtenFrameCount)",
                category: .dictation
            )
            throw SpeechServiceError.emptyTranscription
        }

        await DictationLatencyProbe.shared.beginSession(audioDurationSeconds: audioDurationSeconds)

        do {
            let transcriptionPrompt: String? = if let transcriptionPromptProvider {
                await transcriptionPromptProvider()
            } else {
                nil
            }
            AppLogger.info(
                "Submitting transcription request. promptProvided=\(transcriptionPrompt != nil)",
                category: .dictation
            )

            let transcript = try await transcriptionService.transcribe(
                audioFileAt: recordingFileURL,
                languageCode: languageCode,
                prompt: transcriptionPrompt,
                audioDurationSeconds: audioDurationSeconds
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            cleanupRecordingFile()

            guard !transcript.isEmpty else {
                throw SpeechServiceError.emptyTranscription
            }

            AppLogger.info(
                "Transcription completed successfully. durationSeconds=\(durationDescription), fileSizeBytes=\(recordingFileSizeBytes.map(String.init) ?? "unknown"), writtenFrames=\(writtenFrameCount)",
                category: .dictation
            )
            return transcript
        } catch {
            await DictationLatencyProbe.shared.record(
                .transcriptionFailed,
                note: error.localizedDescription
            )
            cleanupRecordingFile()
            AppLogger.error(
                "Transcription failed. durationSeconds=\(durationDescription), fileSizeBytes=\(recordingFileSizeBytes.map(String.init) ?? "unknown"), writtenFrames=\(writtenFrameCount), error=\(error.localizedDescription)",
                category: .dictation
            )
            throw error
        }
    }

    func cancelRecording() async {
        AppLogger.info("Cancelling active dictation capture", category: .dictation)
        #if os(macOS)
        _ = finishInput()
        isRecording = false
        cleanupRecordingFile()
        audioLevelBridge.emit(0)
        audioLevelBridge.finish()
        #else
        recorder?.stop()
        recorder = nil
        isRecording = false
        stopMetering()
        cleanupRecordingFile()
        #endif
    }

    private var languageCode: String? {
        locale.language.languageCode?.identifier
    }

    private func requestMicrophonePermission() async -> Bool {
        let currentStatus = Self.microphoneAuthorizationStatusDescription
        AppLogger.info(
            "Checking microphone permission. status=\(currentStatus)",
            category: .permissions
        )

        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        AppLogger.info(
            "Microphone permission request completed. granted=\(granted)",
            category: .permissions
        )

        return granted
    }

    private func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }

    #if os(macOS)
    private func startMacRecording() throws {
        let inputNode = audioEngine.inputNode
        let reportedInputFormat = inputNode.outputFormat(forBus: 0)
        guard let outputFormat = TranscriptionUploadAudioFormat.makeMacOutputFormat() else {
            throw SpeechServiceError.unsupportedAudioFormat
        }

        let fileURL = makeRecordingFileURL()
        let recordingFile = try AVAudioFile(
            forWriting: fileURL,
            settings: outputFormat.settings,
            commonFormat: outputFormat.commonFormat,
            interleaved: outputFormat.isInterleaved
        )
        let recordingResources = MacRecordingResources(
            recordingFile: recordingFile,
            outputFormat: outputFormat
        )
        let audioLevelBridge = self.audioLevelBridge

        AppLogger.info(
            """
            Configuring mac transcription capture. \
            reportedInputSampleRate=\(Int(reportedInputFormat.sampleRate)), \
            reportedInputChannels=\(reportedInputFormat.channelCount), \
            outputSampleRate=\(Int(outputFormat.sampleRate)), \
            outputChannels=\(outputFormat.channelCount), \
            fileSampleRate=\(Int(recordingFile.fileFormat.sampleRate)), \
            fileChannels=\(recordingFile.fileFormat.channelCount), \
            fileInterleaved=\(recordingFile.processingFormat.isInterleaved)
            """,
            category: .dictation
        )

        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: nil) { buffer, _ in
            audioLevelBridge.emit(Self.normalizedLevel(from: buffer))

            do {
                guard let snapshot = try recordingResources.snapshot(for: buffer.format) else {
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

                let convertedBuffer = try Self.convertForTranscription(
                    buffer,
                    using: snapshot.converter,
                    outputFormat: outputFormat
                )
                guard convertedBuffer.frameLength > 0 else {
                    return
                }

                try snapshot.recordingFile.write(from: convertedBuffer)
                recordingResources.recordWrite(frameLength: convertedBuffer.frameLength)
            } catch {
                guard recordingResources.shouldLogDroppedBuffer() else {
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
                return
            }
        }

        isTapInstalled = true
        macRecordingResources = recordingResources
        recordingFileURL = fileURL
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    private func finishInput() -> AVAudioFramePosition {
        let writtenFrameCount = macRecordingResources?.totalWrittenFrames() ?? 0

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        audioEngine.reset()
        macRecordingResources?.close()
        macRecordingResources = nil
        return writtenFrameCount
    }

    nonisolated private static func convertForTranscription(
        _ inputBuffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let outputFrameCapacity = TranscriptionUploadAudioFormat.macConvertedFrameCapacity(
            for: inputBuffer.frameLength,
            inputSampleRate: inputBuffer.format.sampleRate
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            throw SpeechServiceError.unsupportedAudioFormat
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let conversionError {
            throw conversionError
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return outputBuffer
        case .error:
            throw SpeechServiceError.unsupportedAudioFormat
        @unknown default:
            throw SpeechServiceError.unsupportedAudioFormat
        }
    }
    #endif

    private func makeRecorderSettings() -> [String: Any] {
        TranscriptionUploadAudioFormat.iOSRecorderSettings
    }

    private func makeRecordingFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Stet-openai-\(UUID().uuidString)")
            .appendingPathExtension(
                {
                    #if os(macOS)
                    TranscriptionUploadAudioFormat.macFileExtension
                    #else
                    TranscriptionUploadAudioFormat.iOSFileExtension
                    #endif
                }()
            )
    }

    private func cleanupRecordingFile() {
        guard let recordingFileURL else { return }
        try? FileManager.default.removeItem(at: recordingFileURL)
        self.recordingFileURL = nil
    }

    private func startMetering(with recorder: AVAudioRecorder) {
        meteringTask?.cancel()
        audioLevelBridge.emit(0.08)
        let audioLevelBridge = self.audioLevelBridge

        meteringTask = Task { [weak recorder] in
            while !Task.isCancelled {
                recorder?.updateMeters()
                let averagePower = recorder?.averagePower(forChannel: 0) ?? -160
                audioLevelBridge.emit(Self.normalizedPowerLevel(averagePower))

                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    private func stopMetering() {
        meteringTask?.cancel()
        meteringTask = nil
        audioLevelBridge.emit(0)
        audioLevelBridge.finish()
    }

    nonisolated private static var microphoneAuthorizationStatusDescription: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return "authorized"
        case .notDetermined:
            return "notDetermined"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        @unknown default:
            return "unknown"
        }
    }

    nonisolated private static func durationDescription(_ durationSeconds: TimeInterval?) -> String {
        guard let durationSeconds else {
            return "unknown"
        }

        return String(format: "%.2f", durationSeconds)
    }

    nonisolated private static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData else {
            return 0.08
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else {
            return 0.08
        }

        var sum: Float = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]

            for index in 0..<frameLength {
                let sample = samples[index]
                sum += sample * sample
            }
        }

        let meanSquare = sum / Float(frameLength * channelCount)
        let rms = sqrt(meanSquare)
        return min(max(Double(rms) * 3.2, 0.08), 1)
    }

    nonisolated private static func normalizedPowerLevel(_ averagePower: Float) -> Double {
        guard averagePower.isFinite else {
            return 0.08
        }

        let clampedPower = max(averagePower, -50)
        let normalized = (clampedPower + 50) / 50
        return min(max(Double(normalized), 0.08), 1)
    }

    nonisolated private static func recordingDurationSeconds(at fileURL: URL) -> TimeInterval? {
        guard let audioFile = try? AVAudioFile(forReading: fileURL) else { return nil }
        let sampleRate = audioFile.fileFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        let duration = TimeInterval(audioFile.length) / sampleRate
        guard duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    nonisolated private static func recordingFileSizeBytes(at fileURL: URL) -> Int64? {
        guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = resourceValues.fileSize else {
            return nil
        }

        return Int64(fileSize)
    }

    nonisolated private static func waitForRecordingFileToStabilize(at fileURL: URL) async {
        var previousFileSize: Int64?

        for _ in 0..<40 {
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
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
