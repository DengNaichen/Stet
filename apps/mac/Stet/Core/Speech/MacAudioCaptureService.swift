@preconcurrency import AVFoundation
#if os(macOS)
@preconcurrency import AudioToolbox
#endif
import Foundation

actor MacAudioCaptureService: AudioCaptureService, AudioLevelSource {
    private let audioLevelBridge: AudioLevelBridge
    #if os(macOS)
    private let macAudioQueueRecorder: MacAudioQueueRecorder
    #endif

    private var recorder: AVAudioRecorder?
    private var recordingFileURL: URL?
    private var isRecording = false
    private var meteringTask: Task<Void, Never>?

    init() {
        let audioLevelBridge = AudioLevelBridge()
        self.audioLevelBridge = audioLevelBridge
        #if os(macOS)
        self.macAudioQueueRecorder = MacAudioQueueRecorder {
            Task {
                await DictationStartupProbe.shared.record(.firstBufferWritten)
            }
        }
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
            await DictationRuntimeProbe.shared.recordCaptureStarted()
        }
        await DictationStartupProbe.shared.record(.audioCaptureStarted)
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
        defer {
            try? FileManager.default.removeItem(at: sourceRecordingFileURL)
        }
        macAudioQueueRecorder.stopRecording()
        self.isRecording = false
        stopMetering()
        finalURL = try Self.convertMacCaptureToUploadFormat(
            from: sourceRecordingFileURL,
            to: makeUploadRecordingFileURL()
        )
        #else
        guard let recorder else {
            throw SpeechServiceError.notRecording
        }
        recorder.stop()
        self.recorder = nil
        self.isRecording = false
        stopMetering()
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
                "AudioQueue"
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
        macAudioQueueRecorder.cancelRecording()
        recorder = nil
        isRecording = false
        stopMetering()
        cleanupRecordingFile()
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
        let fileURL = makeRawMacRecordingFileURL()
        let inputDeviceSelection = AudioInputDeviceManager.preferredInputDeviceForDictation()
        let captureFormat = Self.makeMacCaptureFormat(
            deviceID: inputDeviceSelection?.device.id
        )
        try macAudioQueueRecorder.startRecording(
            to: fileURL,
            outputFormat: captureFormat,
            inputDeviceUID: inputDeviceSelection?.device.uid,
            fileType: kAudioFileCAFType
        )
        recordingFileURL = fileURL
        isRecording = true
        startMacMetering()

        if let inputDeviceSelection {
            AppLogger.info(
                """
                Selected macOS dictation input device. \
                name=\(inputDeviceSelection.device.name), \
                transportType=\(inputDeviceSelection.device.transportType), \
                reason=\(inputDeviceSelection.reason.rawValue)
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

    #if os(macOS)
    private func makeRawMacRecordingFileURL() -> URL {
        makeRecordingFileURL(fileExtension: TranscriptionUploadAudioFormat.macCaptureFileExtension)
    }

    private func makeUploadRecordingFileURL() -> URL {
        makeRecordingFileURL(fileExtension: TranscriptionUploadAudioFormat.macFileExtension)
    }

    nonisolated private static func makeMacCaptureFormat(deviceID: AudioDeviceID?) -> AudioStreamBasicDescription {
        if let deviceID,
           let deviceFormat = AudioInputDeviceManager.inputStreamFormat(for: deviceID),
           Self.isUsableMacCaptureFormat(deviceFormat) {
            return deviceFormat
        }

        if let deviceFormat = AudioInputDeviceManager.defaultInputStreamFormat(),
           Self.isUsableMacCaptureFormat(deviceFormat) {
            return deviceFormat
        }

        return AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }

    nonisolated private static func isUsableMacCaptureFormat(_ format: AudioStreamBasicDescription) -> Bool {
        format.mFormatID == kAudioFormatLinearPCM &&
        format.mSampleRate > 0 &&
        format.mChannelsPerFrame > 0 &&
        format.mBytesPerFrame > 0 &&
        format.mFramesPerPacket > 0 &&
        format.mBytesPerPacket > 0
    }

    nonisolated private static func convertMacCaptureToUploadFormat(
        from sourceURL: URL,
        to destinationURL: URL
    ) throws -> URL {
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        guard let outputFormat = TranscriptionUploadAudioFormat.makeMacOutputFormat() else {
            throw SpeechServiceError.failedToStart
        }
        guard let converter = LinearPCMConversion.makeConverter(
            from: sourceFile.processingFormat,
            to: outputFormat
        ) else {
            throw LinearPCMConversion.ConversionError.conversionFailed
        }

        AppLogger.info(
            """
            Converting mac capture to upload format. \
            sourceSampleRate=\(Int(sourceFile.processingFormat.sampleRate)), \
            sourceChannels=\(sourceFile.processingFormat.channelCount), \
            sourceCommonFormat=\(String(describing: sourceFile.processingFormat.commonFormat)), \
            destinationSampleRate=\(Int(outputFormat.sampleRate)), \
            destinationChannels=\(outputFormat.channelCount), \
            destinationCommonFormat=\(String(describing: outputFormat.commonFormat))
            """,
            category: .dictation
        )

        do {
            let destinationFile = try AVAudioFile(
                forWriting: destinationURL,
                settings: outputFormat.settings,
                commonFormat: outputFormat.commonFormat,
                interleaved: outputFormat.isInterleaved
            )
            let inputFormat = sourceFile.processingFormat
            let inputBufferCapacity: AVAudioFrameCount = 4_096

            while sourceFile.framePosition < sourceFile.length {
                let remainingFrameCount = sourceFile.length - sourceFile.framePosition
                let frameCountToRead = AVAudioFrameCount(
                    min(Int64(inputBufferCapacity), remainingFrameCount)
                )
                guard let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: inputFormat,
                    frameCapacity: frameCountToRead
                ) else {
                    throw LinearPCMConversion.ConversionError.outputBufferCreationFailed
                }

                try sourceFile.read(into: inputBuffer, frameCount: frameCountToRead)
                guard inputBuffer.frameLength > 0 else {
                    break
                }

                let convertedBuffer = try LinearPCMConversion.convert(
                    inputBuffer,
                    using: converter,
                    outputFormat: outputFormat
                )

                if convertedBuffer.frameLength > 0 {
                    try destinationFile.write(from: convertedBuffer)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }

        return destinationURL
    }
    #endif

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

    #if os(macOS)
    private func startMacMetering() {
        meteringTask?.cancel()
        audioLevelBridge.emit(0.08)
        let audioLevelBridge = self.audioLevelBridge
        let macAudioQueueRecorder = self.macAudioQueueRecorder

        Task {
            await DictationRuntimeProbe.shared.markMeteringStarted()
        }

        meteringTask = Task {
            while !Task.isCancelled {
                let averagePower = macAudioQueueRecorder.currentAveragePowerLevel() ?? -160
                audioLevelBridge.emit(AudioLevelNormalizer.normalizedPowerLevel(averagePower))
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }
    #endif

    private func stopMetering() {
        Task {
            await DictationRuntimeProbe.shared.markMeteringStopped()
        }
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
