@preconcurrency import AVFoundation
import Foundation

actor MacAudioCaptureService: AudioCaptureService, AudioLevelSource {
    private let audioLevelBridge: AudioLevelBridge
    #if os(macOS)
    private let macAudioFileRecorder: MacAudioFileRecorder
    #endif

    private var recorder: AVAudioRecorder?
    private var recordingFileURL: URL?
    private var isRecording = false
    private var meteringTask: Task<Void, Never>?

    init() {
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

        AppLogger.info("Starting audio capture", category: .dictation)
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
        AppLogger.info("Audio capture started successfully", category: .dictation)
    }

    func stopRecording() async throws -> (url: URL, duration: TimeInterval?) {
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
            Stopping audio capture. \
            durationSeconds=\(durationDescription), \
            fileSizeBytes=\(recordingFileSizeBytes.map(String.init) ?? "unknown"), \
            writtenFrames=\(writtenFrameCount)
            """,
            category: .dictation
        )

        if writtenFrameCount == 0 || (audioDurationSeconds ?? 0) < 0.1 || (recordingFileSizeBytes ?? 0) <= 64 {
            AppLogger.warning("Skipping file because audio frames were insignificant.", category: .dictation)
            try? FileManager.default.removeItem(at: recordingFileURL)
            self.recordingFileURL = nil
            throw SpeechServiceError.emptyTranscription
        }

        let finalURL = recordingFileURL
        self.recordingFileURL = nil
        return (url: finalURL, duration: audioDurationSeconds)
    }

    func cancelRecording() async {
        AppLogger.info("Cancelling active audio capture", category: .dictation)
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
            .appendingPathComponent("Stet-capture-\(UUID().uuidString)")
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
        case .authorized: return "authorized"
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        @unknown default: return "unknown"
        }
    }

    nonisolated private static func durationDescription(_ durationSeconds: TimeInterval?) -> String {
        guard let durationSeconds else { return "unknown" }
        return String(format: "%.2f", durationSeconds)
    }

    nonisolated private static func recordingDurationSeconds(at fileURL: URL) -> TimeInterval? {
        guard let audioFile = try? AVAudioFile(forReading: fileURL) else { return nil }
        let sampleRate = audioFile.fileFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        return TimeInterval(audioFile.length) / sampleRate
    }

    nonisolated private static func recordingFileSizeBytes(at fileURL: URL) -> Int64? {
        guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = resourceValues.fileSize else {
            return nil
        }
        return Int64(fileSize)
    }
}
