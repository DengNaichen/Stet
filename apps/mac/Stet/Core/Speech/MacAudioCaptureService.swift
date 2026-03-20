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
        self.macAudioFileRecorder = MacAudioFileRecorder(
            audioLevelHandler: { level in
                audioLevelBridge.emit(level)
            },
            onFirstRecordedBufferWritten: {
                Task {
                    await DictationStartupProbe.shared.record(.firstBufferWritten)
                }
            }
        )
        #endif
    }



    func makeAudioLevelStream() async -> AsyncStream<Double> {
        audioLevelBridge.makeStream()
    }

    func startRecording() async throws {
        Task {
            await DictationRuntimeProbe.shared.markAction("startRecordingRequested")
        }
        guard !isRecording else {
            Task {
                await DictationRuntimeProbe.shared.markCaptureStartError("alreadyRecording")
            }
            throw SpeechServiceError.alreadyRecording
        }

        AppLogger.info("Starting audio capture", category: .dictation)
        let microphoneGranted = await requestMicrophonePermission()
        await DictationStartupProbe.shared.record(
            .microphonePermissionResolved,
            note: "granted=\(microphoneGranted)"
        )
        guard microphoneGranted else {
            AppLogger.warning("Microphone permission denied before recording start", category: .permissions)
            Task {
                await DictationRuntimeProbe.shared.markCaptureStartError("permissionDenied")
            }
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
        Task {
            await DictationRuntimeProbe.shared.markCaptureStarted()
        }
        await DictationStartupProbe.shared.record(.audioCaptureStarted)
    }

    func activateRecordingWindow() async throws {
        guard isRecording else {
            throw SpeechServiceError.notRecording
        }

        #if os(macOS)
        macAudioFileRecorder.activateRecordingWindow()
        #endif
    }

    func stopRecording() async throws -> (url: URL, duration: TimeInterval?) {
        Task {
            await DictationRuntimeProbe.shared.markAudioStopRequested()
        }
        guard isRecording, let recordingFileURL else {
            throw SpeechServiceError.notRecording
        }

        let finalURL: URL
        #if os(macOS)
        let sourceRecordingFileURL = recordingFileURL
        self.recordingFileURL = nil
        let recordingOutcome = await macAudioFileRecorder.stopRecording(writtenFileAt: sourceRecordingFileURL)
        self.isRecording = false
        finishCaptureStreams()

        if let captureDiagnosticsSummary = recordingOutcome.captureDiagnosticsSummary {
            if UserDefaults.standard.bool(forKey: MacPreferences.dictationPerfTracingEnabled) {
                AppLogger.warning(
                    """
                    Capture summary. \
                    didWriteAudio=\(recordingOutcome.didWriteAudio) \
                    \(captureDiagnosticsSummary)
                    """,
                    category: .dictation
                )
            }
            Task {
                await DictationRuntimeProbe.shared.markAction(
                    "frontendCaptureSummary",
                    details: captureDiagnosticsSummary
                )
            }
        }

        guard recordingOutcome.didWriteAudio else {
            try? FileManager.default.removeItem(at: sourceRecordingFileURL)
            AppLogger.warning("Discarding macOS capture because no audio was recorded after activation.", category: .dictation)
            throw SpeechServiceError.emptyTranscription
        }

        finalURL = sourceRecordingFileURL
        #else
        guard let recorder else {
            throw SpeechServiceError.notRecording
        }
        recorder.stop()
        self.recorder = nil
        self.isRecording = false
        finishCaptureStreams()
        finalURL = recordingFileURL
        #endif

        let audioDurationSeconds = Self.recordingDurationSeconds(at: finalURL)
        let durationDescription = Self.durationDescription(audioDurationSeconds)
        let recordingFileSizeBytes = Self.recordingFileSizeBytes(at: finalURL)

        AppLogger.info(
            """
            Stopping audio capture. \
            durationSeconds=\(durationDescription), \
            fileSizeBytes=\(recordingFileSizeBytes.map(String.init) ?? "unknown"), \
            recorderType=\({
                #if os(macOS)
                "AVAudioEngine"
                #else
                "AVAudioRecorder"
                #endif
            }())
            """,
            category: .dictation
        )
        Task {
            await DictationRuntimeProbe.shared.markCaptureStopped()
        }

        if (audioDurationSeconds ?? 0) < 0.1 || (recordingFileSizeBytes ?? 0) <= 64 {
            AppLogger.warning("Skipping file because audio frames were insignificant.", category: .dictation)
            try? FileManager.default.removeItem(at: finalURL)
            throw SpeechServiceError.emptyTranscription
        }

        return (url: finalURL, duration: audioDurationSeconds)
    }

    func cancelRecording() async {
        AppLogger.info("Cancelling active audio capture", category: .dictation)
        Task {
            await DictationRuntimeProbe.shared.markCaptureCancelled()
        }
        #if os(macOS)
        macAudioFileRecorder.cancelRecording()
        recorder = nil
        isRecording = false
        finishCaptureStreams()
        cleanupRecordingFile()
        #else
        recorder?.stop()
        recorder = nil
        isRecording = false
        finishCaptureStreams()
        cleanupRecordingFile()
        #endif
    }

    func prewarm() async {
        #if os(macOS)
        macAudioFileRecorder.prewarm()
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
            throw SpeechServiceError.failedToStart
        }

        let fileURL = makeRecordingFileURL()
        try macAudioFileRecorder.startRecording(
            to: fileURL,
            outputFormat: outputFormat
        )
        recordingFileURL = fileURL
        isRecording = true
        audioLevelBridge.emit(0.08)

        if let defaultInputDevice = AudioInputDeviceManager.defaultInputDevice() {
            AppLogger.info(
                """
                Using system-default macOS dictation input device. \
                name=\(defaultInputDevice.name), \
                transportType=\(defaultInputDevice.transportType)
                """,
                category: .dictation
            )
        }
    }
    #endif

    private func makeRecorderSettings() -> [String: Any] {
        TranscriptionUploadAudioFormat.iOSRecorderSettings
    }

    private func makeRecordingFileURL(fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Stet-capture-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }

    private func makeRecordingFileURL() -> URL {
        makeRecordingFileURL(
            fileExtension: {
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

    private func finishCaptureStreams() {
        Task {
            await DictationRuntimeProbe.shared.markMeteringStopped()
        }
        meteringTask?.cancel()
        meteringTask = nil
        audioLevelBridge.emit(0)
        audioLevelBridge.finish()
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
