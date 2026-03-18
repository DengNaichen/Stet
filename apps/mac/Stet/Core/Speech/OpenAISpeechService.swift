@preconcurrency import AVFoundation
import Foundation

actor OpenAISpeechService: SpeechService, AudioLevelSource {
    private let transcriptionService: any AudioFileTranscriptionService
    private let locale: Locale
    private let transcriptionPromptProvider: (@Sendable () async -> String?)?
    private let audioLevelBridge: AudioLevelBridge
    #if os(macOS)
    private let macAudioFileRecorder: MacAudioFileRecorder
    #endif

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
        let audioLevelBridge = AudioLevelBridge()
        self.audioLevelBridge = audioLevelBridge
        #if os(macOS)
        self.macAudioFileRecorder = MacAudioFileRecorder { level in
            audioLevelBridge.emit(level)
        }
        #endif
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
        let writtenFrameCount = await macAudioFileRecorder.stopRecording(writtenFileAt: recordingFileURL)
        self.isRecording = false
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
        macAudioFileRecorder.cancelRecording()
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
        guard let outputFormat = TranscriptionUploadAudioFormat.makeMacOutputFormat() else {
            throw SpeechServiceError.unsupportedAudioFormat
        }

        let fileURL = makeRecordingFileURL()
        recordingFileURL = fileURL

        do {
            try macAudioFileRecorder.startRecording(
                to: fileURL,
                outputFormat: outputFormat
            )
            isRecording = true
        } catch {
            cleanupRecordingFile()
            throw error
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
                audioLevelBridge.emit(AudioLevelNormalizer.normalizedPowerLevel(averagePower))

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
