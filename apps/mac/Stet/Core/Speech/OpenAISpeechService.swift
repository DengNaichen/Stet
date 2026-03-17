@preconcurrency import AVFoundation
import Foundation
#if os(macOS)
import AudioToolbox
#endif

actor OpenAISpeechService: SpeechService, AudioLevelStreaming {
    private let transcriptionService: any AudioFileTranscriptionService
    private let locale: Locale
    private let transcriptionPromptProvider: (@Sendable () async -> String?)?
    #if os(macOS)
    private let preferredInputDeviceID: AudioDeviceID?
    private let audioEngine = AVAudioEngine()
    private var isTapInstalled = false
    #endif
    private let audioLevelBridge = AudioLevelBridge()

    private var recorder: AVAudioRecorder?
    private var recordingFileURL: URL?
    private var isRecording = false
    private var meteringTask: Task<Void, Never>?

    init(
        transcriptionService: any AudioFileTranscriptionService,
        locale: Locale = .autoupdatingCurrent,
        preferredInputDeviceID: UInt32? = nil,
        transcriptionPromptProvider: (@Sendable () async -> String?)? = nil
    ) {
        self.transcriptionService = transcriptionService
        self.locale = locale
        #if os(macOS)
        self.preferredInputDeviceID = preferredInputDeviceID
        #endif
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

        let audioDurationSeconds = Self.recordingDurationSeconds(at: recordingFileURL)
        let durationDescription = Self.durationDescription(audioDurationSeconds)
        let recordingFileSizeBytes = Self.recordingFileSizeBytes(at: recordingFileURL)
        AppLogger.info(
            """
            Stopping dictation capture and starting transcription. \
            durationSeconds=\(durationDescription), \
            fileSizeBytes=\(recordingFileSizeBytes.map(String.init) ?? "unknown")
            """,
            category: .dictation
        )

        #if os(macOS)
        finishInput()
        self.isRecording = false
        #else
        guard let recorder else {
            throw SpeechServiceError.notRecording
        }
        recorder.stop()
        self.recorder = nil
        self.isRecording = false
        stopMetering()
        #endif

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
                "Transcription completed successfully. durationSeconds=\(durationDescription)",
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
                "Transcription failed. durationSeconds=\(durationDescription), error=\(error.localizedDescription)",
                category: .dictation
            )
            throw error
        }
    }

    func cancelRecording() async {
        AppLogger.info("Cancelling active dictation capture", category: .dictation)
        #if os(macOS)
        finishInput()
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
        applyPreferredInputDeviceIfNeeded(inputNode: inputNode)
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let fileURL = makeRecordingFileURL()
        let recordingFile = try AVAudioFile(forWriting: fileURL, settings: inputFormat.settings)
        let audioLevelBridge = self.audioLevelBridge

        AppLogger.info(
            """
            Configuring mac transcription capture. \
            inputSampleRate=\(Int(inputFormat.sampleRate)), \
            inputChannels=\(inputFormat.channelCount), \
            fileSampleRate=\(Int(recordingFile.fileFormat.sampleRate)), \
            fileChannels=\(recordingFile.fileFormat.channelCount), \
            fileInterleaved=\(recordingFile.processingFormat.isInterleaved)
            """,
            category: .dictation
        )

        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { buffer, _ in
            try? recordingFile.write(from: buffer)
            audioLevelBridge.emit(Self.normalizedLevel(from: buffer))
        }

        isTapInstalled = true
        recordingFileURL = fileURL
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    private func finishInput() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        audioEngine.reset()
    }

    private func applyPreferredInputDeviceIfNeeded(inputNode: AVAudioInputNode) {
        guard let preferredInputDeviceID else { return }
        guard let audioUnit = inputNode.audioUnit else { return }

        var deviceID = preferredInputDeviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            AppLogger.warning("Unable to switch input device. status=\(status)")
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
}
