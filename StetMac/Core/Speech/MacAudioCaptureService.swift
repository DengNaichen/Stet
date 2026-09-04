@preconcurrency import AVFoundation
import Foundation
import os
#if os(macOS)
    import StetVisuals
#endif

actor MacAudioCaptureService: AudioCaptureService, AudioLevelSource {
    private let audioLevelBridge: AudioLevelBridge
    #if os(macOS)
        private let audioFeatureBridge: AudioFeatureBridge
        private let audioCaptureEventBridge: AudioCaptureEventBridge
    #endif
    #if os(macOS)
        private let macAudioFileRecorder: MacCaptureAudioFileRecorder
    #endif

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet", category: "AudioCapture")

    private var recorder: AVAudioRecorder?
    private var recordingFileURL: URL?
    private var isRecording = false
    private var meteringTask: Task<Void, Never>?

    init() {
        let audioLevelBridge = AudioLevelBridge()
        self.audioLevelBridge = audioLevelBridge
        #if os(macOS)
            let audioFeatureBridge = AudioFeatureBridge()
            let audioCaptureEventBridge = AudioCaptureEventBridge()
            self.audioFeatureBridge = audioFeatureBridge
            self.audioCaptureEventBridge = audioCaptureEventBridge
            self.macAudioFileRecorder = MacCaptureAudioFileRecorder(
                audioLevelHandler: { level in
                    audioLevelBridge.emit(level)
                },
                audioFeatureHandler: { features in
                    audioFeatureBridge.emit(features)
                },
                audioFrameHandler: { samples in
                    audioCaptureEventBridge.emit(samples: samples)
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

    #if os(macOS)
        func makeAudioFeatureStream() async -> AsyncStream<MacDictationCapsuleVisualSignals> {
            audioFeatureBridge.makeStream()
        }

        func makeAudioCaptureFrameStream() -> AsyncStream<AudioCaptureFrame> {
            audioCaptureEventBridge.makeStream()
        }

        @discardableResult
        func beginNextAudioCaptureEpoch() -> Int64 {
            audioCaptureEventBridge.beginNextEpoch()
        }

        func currentAudioCaptureEpoch() -> UInt64 {
            audioCaptureEventBridge.currentEpoch()
        }

        func currentAudioCaptureSamplePosition() -> Int64 {
            audioCaptureEventBridge.currentSamplePosition()
        }

        func startContinuousCapture() async throws {
            guard await requestMicrophonePermission() else {
                throw SpeechServiceError.microphonePermissionDenied
            }
            guard let outputFormat = TranscriptionUploadAudioFormat.makeMacOutputFormat() else {
                throw SpeechServiceError.failedToStart
            }
            let selectedInputDevice =
                await MainActor.run {
                    AudioDeviceSelectionManager.shared.currentRecordingDevice()
                }
                ?? AudioInputDeviceManager.defaultInputDevice()
            try macAudioFileRecorder.startCapture(
                outputFormat: outputFormat,
                selectedDevice: selectedInputDevice
            )
        }

        func stopContinuousCapture() {
            macAudioFileRecorder.stopCapture()
            audioCaptureEventBridge.finish()
        }
    #endif

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

        logger.info("Starting audio capture")
        let startRecordingStartedAt = ProcessInfo.processInfo.systemUptime
        let permissionStartedAt = ProcessInfo.processInfo.systemUptime
        let microphoneGranted = await requestMicrophonePermission()
        let microphonePermissionMs = Self.elapsedMilliseconds(since: permissionStartedAt)
        Self.logStartupTiming(
            "microphonePermissionMs=\(Self.formatMilliseconds(microphonePermissionMs)) granted=\(microphoneGranted)"
        )
        await DictationStartupProbe.shared.record(
            .microphonePermissionResolved,
            note:
                "granted=\(microphoneGranted) microphonePermissionMs=\(Self.formatMilliseconds(microphonePermissionMs))"
        )
        guard microphoneGranted else {
            logger.warning("Microphone permission denied before recording start")
            Task {
                await DictationRuntimeProbe.shared.markCaptureStartError("permissionDenied")
            }
            throw SpeechServiceError.microphonePermissionDenied
        }

        try Task.checkCancellation()
        try configureAudioSession()

        #if os(macOS)
            let macRecordingStartedAt = ProcessInfo.processInfo.systemUptime
            let selectedInputDevice = try await startMacRecording()
            let startMacRecordingMs = Self.elapsedMilliseconds(since: macRecordingStartedAt)
            Self.logStartupTiming(
                """
                startMacRecordingMs=\(Self.formatMilliseconds(startMacRecordingMs)) \
                selectedDevice=\(selectedInputDevice?.name ?? "none") \
                transportType=\(selectedInputDevice?.transportType ?? 0)
                """
            )
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
        logger.info("Audio capture started successfully")
        Task {
            await DictationRuntimeProbe.shared.markCaptureStarted()
        }
        let startRecordingMs = Self.elapsedMilliseconds(since: startRecordingStartedAt)
        await DictationStartupProbe.shared.record(
            .audioCaptureStarted,
            note: "startRecordingMs=\(Self.formatMilliseconds(startRecordingMs))"
        )
    }

    func activateRecordingWindow() async throws {
        guard isRecording else {
            throw SpeechServiceError.notRecording
        }

        #if os(macOS)
            try macAudioFileRecorder.activateRecordingWindow()
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
                    logger.warning(
                        """
                        Capture summary. \
                        didWriteAudio=\(recordingOutcome.didWriteAudio) \
                        \(captureDiagnosticsSummary)
                        """
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
                logger.warning("Discarding macOS capture because no audio was recorded after activation.")
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

        logger.info(
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
            """
        )
        Task {
            await DictationRuntimeProbe.shared.markCaptureStopped()
        }

        if (audioDurationSeconds ?? 0) < 0.1 || (recordingFileSizeBytes ?? 0) <= 64 {
            logger.warning("Skipping file because audio frames were insignificant.")
            try? FileManager.default.removeItem(at: finalURL)
            throw SpeechServiceError.emptyTranscription
        }

        return (url: finalURL, duration: audioDurationSeconds)
    }

    func cancelRecording() async {
        logger.info("Cancelling active audio capture")
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
        logger.info("Checking microphone permission. status=\(currentStatus)")

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
        private func startMacRecording() async throws -> AudioHardwareDevice? {
            guard let outputFormat = TranscriptionUploadAudioFormat.makeMacOutputFormat() else {
                throw SpeechServiceError.failedToStart
            }

            let selectedInputDevice =
                await MainActor.run {
                    AudioDeviceSelectionManager.shared.currentRecordingDevice()
                }
                ?? AudioInputDeviceManager.defaultInputDevice()
            let fileURL = makeRecordingFileURL()
            try macAudioFileRecorder.startRecording(
                to: fileURL,
                outputFormat: outputFormat,
                selectedDevice: selectedInputDevice
            )
            recordingFileURL = fileURL
            isRecording = true
            audioLevelBridge.emit(0.08)
            #if os(macOS)
                audioFeatureBridge.emit(.zero)
            #endif

            if let selectedInputDevice {
                logger.info(
                    """
                    Using macOS dictation input device. \
                    name=\(selectedInputDevice.name), \
                    transportType=\(selectedInputDevice.transportType)
                    """
                )
            }

            return selectedInputDevice
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
        // The capture service is reused across sessions. Emitting silence keeps
        // the current UI honest without tearing down the stream permanently.
        audioLevelBridge.emit(0)
        #if os(macOS)
            audioFeatureBridge.emit(.zero)
        #endif
    }

    nonisolated private static var microphoneAuthorizationStatusDescription: String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return "granted"
        case .undetermined: return "undetermined"
        case .denied: return "denied"
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
            let fileSize = resourceValues.fileSize
        else {
            return nil
        }
        return Int64(fileSize)
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

#if os(macOS)
    extension MacAudioCaptureService: AudioFeatureSource {}
#endif
