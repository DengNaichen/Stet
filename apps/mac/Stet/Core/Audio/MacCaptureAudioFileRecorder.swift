#if os(macOS)
@preconcurrency import AVFoundation
import CoreAudio
import CoreMedia
import Foundation

final class MacCaptureAudioFileRecorder: NSObject, @unchecked Sendable {
    private struct InputDeviceCandidate {
        let device: AudioHardwareDevice?
        let reason: Reason

        enum Reason: String {
            case selected
            case noExplicitDeviceFallback
            case builtInFallback
            case systemDefaultFallback
        }
    }

    private enum Configuration {
        static let startupRetryCount = 4
        static let startupRetryDelaySeconds = 0.15
    }

    private enum CaptureError: LocalizedError {
        case noCaptureDeviceAvailable
        case selectedDeviceUnavailable(target: String, available: [String])
        case failedToCreatePCMBuffer
        case failedToReadSampleBuffer(status: OSStatus)
        case unsupportedSampleBufferFormat
        case failedToConfigureSession(reason: String)
        case failedToStartSession(device: String)

        var errorDescription: String? {
            switch self {
            case .noCaptureDeviceAvailable:
                return "No audio capture device is available."
            case .selectedDeviceUnavailable(let target, let available):
                let availableDescription = available.isEmpty ? "none" : available.joined(separator: ", ")
                return "Selected capture device \(target) was unavailable. available=\(availableDescription)"
            case .failedToCreatePCMBuffer:
                return "Failed to create a PCM buffer for macOS capture."
            case .failedToReadSampleBuffer(let status):
                return "Failed to read an audio sample buffer. osstatus=\(status)"
            case .unsupportedSampleBufferFormat:
                return "Received an unsupported macOS audio sample format."
            case .failedToConfigureSession(let reason):
                return "Failed to configure the macOS capture session. reason=\(reason)"
            case .failedToStartSession(let device):
                return "Failed to start the macOS capture session for \(device)."
            }
        }
    }

    private struct CaptureResources {
        let session: AVCaptureSession
        let input: AVCaptureDeviceInput
        let output: AVCaptureAudioDataOutput
        let device: AVCaptureDevice
    }

    private let firstBufferLock = NSLock()
    private let stateLock = NSLock()
    private let captureQueue = DispatchQueue(
        label: "Stet.MacCaptureAudioFileRecorder.capture",
        qos: .userInitiated
    )
    private let audioLevelHandler: @Sendable (Double) -> Void
    private let onFirstRecordedBufferWritten: @Sendable () -> Void

    private var captureResources: CaptureResources?
    private var activeSession: MacAudioFileRecordingSession?
    private var hasWrittenFirstRecordedBuffer = false

    init(
        audioLevelHandler: @escaping @Sendable (Double) -> Void = { _ in },
        onFirstRecordedBufferWritten: @escaping @Sendable () -> Void = {}
    ) {
        self.audioLevelHandler = audioLevelHandler
        self.onFirstRecordedBufferWritten = onFirstRecordedBufferWritten
        super.init()
    }

    nonisolated func startRecording(
        to fileURL: URL,
        outputFormat: AVAudioFormat
    ) throws {
        precondition(currentSession() == nil, "MacCaptureAudioFileRecorder is already recording.")

        let candidates = inputDeviceCandidates()
        Self.logStartupTiming(
            "captureRecorderStart candidates=\(candidates.map { Self.describe(candidate: $0) }.joined(separator: ","))"
        )
        var startupError: Error?

        for candidate in candidates {
            let attemptStartedAt = ProcessInfo.processInfo.systemUptime
            do {
                try startRecordingAttempt(
                    to: fileURL,
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
                    AppLogger.info(
                        "macOS capture recovered using AVCapture fallback input device strategy. reason=\(candidate.reason.rawValue), device=\(candidate.device?.name ?? "systemDefault")",
                        category: .dictation
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
                AppLogger.warning(
                    "macOS AVCapture attempt failed. reason=\(candidate.reason.rawValue), device=\(candidate.device?.name ?? "systemDefault"), error=\(error.localizedDescription)",
                    category: .dictation
                )
                _ = finishSession()
                Thread.sleep(forTimeInterval: 0.1)
            }
        }

        if let startupError {
            AppLogger.error(
                "All macOS AVCapture input device candidates failed. error=\(startupError.localizedDescription)",
                category: .dictation
            )
        }

        throw SpeechServiceError.failedToStart
    }

    nonisolated func activateRecordingWindow() throws {
        try currentSession()?.activateRecordingWindow()
    }

    nonisolated func stopRecording(writtenFileAt fileURL: URL) async -> MacAudioFileRecordingOutcome {
        let outcome = finishSession()
        if outcome.didWriteAudio {
            await MacAudioFileRecorder.waitForFileToStabilize(at: fileURL)
        }
        return outcome
    }

    nonisolated func cancelRecording() {
        _ = finishSession()
    }

    nonisolated func prewarm() {
        _ = Self.availableCaptureDevices()
    }

    deinit {
        _ = finishSession()
    }

    nonisolated private func startRecordingAttempt(
        to fileURL: URL,
        outputFormat: AVAudioFormat,
        inputDevice: AudioHardwareDevice?,
        candidateReason: InputDeviceCandidate.Reason
    ) throws {
        let captureDeviceStartedAt = ProcessInfo.processInfo.systemUptime
        let captureDevice = try Self.resolveCaptureDevice(for: inputDevice)
        let captureDeviceMs = Self.elapsedMilliseconds(since: captureDeviceStartedAt)

        let resources = try Self.makeCaptureResources(
            for: captureDevice,
            delegate: self,
            queue: captureQueue
        )

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
            voiceProcessingEnabled: false,
            voiceProcessingFallbackReason: "input-only avcapture capture"
        )

        firstBufferLock.lock()
        hasWrittenFirstRecordedBuffer = false
        firstBufferLock.unlock()

        setCurrentSession(recordingSession)
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
                recordingFileMs=\(Self.formatMilliseconds(recordingFileMs)) \
                sessionStartMs=\(Self.formatMilliseconds(sessionStartMs))
                """
            )
        } catch {
            _ = finishSession()
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
                AppLogger.info(
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
                    """,
                    category: .dictation
                )
                break
            }

            Self.logStartupTiming(
                "captureRecorderSessionStartFailed attempt=\(attempt) attemptMs=\(Self.formatMilliseconds(attemptMs))"
            )
            AppLogger.warning(
                "macOS AVCapture session start failed on attempt \(attempt). Retrying...",
                category: .dictation
            )
            Thread.sleep(forTimeInterval: Configuration.startupRetryDelaySeconds)
        }

        guard didStart else {
            AppLogger.error(
                "Failed to start the macOS AVCapture session after retries. captureDevice=\(resources.device.localizedName)",
                category: .dictation
            )
            throw CaptureError.failedToStartSession(device: resources.device.localizedName)
        }
    }

    nonisolated private func handleIncomingSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let session = currentSession() else {
            return
        }

        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        do {
            let inputBuffer = try Self.pcmBuffer(from: sampleBuffer)
            audioLevelHandler(AudioLevelNormalizer.normalizedLevel(from: inputBuffer))

            guard let snapshot = try session.snapshot(for: inputBuffer.format) else {
                return
            }

            if snapshot.didCreateConverter {
                AppLogger.info(
                    """
                    Prepared mac transcription converter from AVCapture audio buffer. \
                    actualInputSampleRate=\(Int(inputBuffer.format.sampleRate)), \
                    actualInputChannels=\(inputBuffer.format.channelCount), \
                    actualInputCommonFormat=\(String(describing: inputBuffer.format.commonFormat)), \
                    actualInputInterleaved=\(inputBuffer.format.isInterleaved)
                    """,
                    category: .dictation
                )
            }

            let convertedBuffer = try LinearPCMConversion.convert(
                inputBuffer,
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
                "Dropping AVCapture audio buffer before transcription write. error=\(error.localizedDescription)",
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
        tearDownCaptureSession()

        firstBufferLock.lock()
        hasWrittenFirstRecordedBuffer = false
        firstBufferLock.unlock()

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

    nonisolated private func inputDeviceCandidates() -> [InputDeviceCandidate] {
        let selectedDevice = Self.selectedRecordingDevice()
        let builtInDevice = AudioInputDeviceManager.builtInInputDevice()
        let defaultInputDevice = AudioInputDeviceManager.defaultInputDevice()

        var candidates: [InputDeviceCandidate] = []
        var seenUIDs = Set<String>()
        var hasSystemDefaultCandidate = false

        func append(_ device: AudioHardwareDevice?, reason: InputDeviceCandidate.Reason) {
            if let device {
                guard seenUIDs.insert(device.uid).inserted else {
                    return
                }
            } else {
                guard !hasSystemDefaultCandidate else {
                    return
                }
                hasSystemDefaultCandidate = true
            }

            candidates.append(InputDeviceCandidate(device: device, reason: reason))
        }

        if let selectedDevice {
            append(selectedDevice, reason: .selected)

            if Self.defaultRouteMatches(device: selectedDevice, defaultInputDevice: defaultInputDevice) {
                append(nil, reason: .noExplicitDeviceFallback)
            }

            return candidates
        }

        append(nil, reason: .noExplicitDeviceFallback)
        append(builtInDevice, reason: .builtInFallback)
        append(defaultInputDevice, reason: .systemDefaultFallback)
        return candidates
    }

    private static func makeCaptureResources(
        for device: AVCaptureDevice,
        delegate: any AVCaptureAudioDataOutputSampleBufferDelegate,
        queue: DispatchQueue
    ) throws -> CaptureResources {
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(delegate, queue: queue)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddInput(input) else {
            throw CaptureError.failedToConfigureSession(reason: "cannot add input \(device.localizedName)")
        }
        session.addInput(input)

        guard session.canAddOutput(output) else {
            throw CaptureError.failedToConfigureSession(reason: "cannot add audio output")
        }
        session.addOutput(output)

        return CaptureResources(
            session: session,
            input: input,
            output: output,
            device: device
        )
    }

    private static func resolveCaptureDevice(for device: AudioHardwareDevice?) throws -> AVCaptureDevice {
        let availableDevices = availableCaptureDevices()

        guard let device else {
            if let defaultDevice = AVCaptureDevice.default(for: .audio) {
                return defaultDevice
            }

            if let fallbackDevice = availableDevices.first {
                return fallbackDevice
            }

            throw CaptureError.noCaptureDeviceAvailable
        }

        if let exactUIDMatch = availableDevices.first(where: { $0.uniqueID == device.uid }) {
            return exactUIDMatch
        }

        if let exactNameMatch = availableDevices.first(where: { $0.localizedName == device.name }) {
            return exactNameMatch
        }

        if device.isBuiltIn,
           let builtInLikeDevice = availableDevices.first(where: {
               $0.localizedName.localizedCaseInsensitiveContains("microphone")
                   || $0.localizedName.localizedCaseInsensitiveContains("macbook")
           }) {
            return builtInLikeDevice
        }

        throw CaptureError.selectedDeviceUnavailable(
            target: "\(device.name) (\(device.uid))",
            available: availableDevices.map { "\($0.localizedName) (\($0.uniqueID))" }
        )
    }

    private static func availableCaptureDevices() -> [AVCaptureDevice] {
        var devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices

        if devices.isEmpty {
            devices = AVCaptureDevice.devices(for: .audio)
        }

        return devices
    }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw CaptureError.unsupportedSampleBufferFormat
        }

        var streamDescription = streamDescriptionPointer.pointee
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw CaptureError.unsupportedSampleBufferFormat
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            throw CaptureError.failedToCreatePCMBuffer
        }
        pcmBuffer.frameLength = frameCount

        var audioBufferListSize = Int(
            MemoryLayout<AudioBufferList>.size +
                max(Int(format.channelCount) - 1, 0) * MemoryLayout<AudioBuffer>.size
        )
        let audioBufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: audioBufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { audioBufferListPointer.deallocate() }

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &audioBufferListSize,
            bufferListOut: audioBufferListPointer.assumingMemoryBound(to: AudioBufferList.self),
            bufferListSize: audioBufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else {
            throw CaptureError.failedToReadSampleBuffer(status: status)
        }

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(
            audioBufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        )
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
        guard sourceBuffers.count == destinationBuffers.count else {
            throw CaptureError.unsupportedSampleBufferFormat
        }

        for index in 0..<sourceBuffers.count {
            let source = sourceBuffers[index]
            let destination = destinationBuffers[index]
            guard let sourceData = source.mData,
                  let destinationData = destination.mData else {
                throw CaptureError.unsupportedSampleBufferFormat
            }

            let byteCount = Int(min(source.mDataByteSize, destination.mDataByteSize))
            memcpy(destinationData, sourceData, byteCount)
            destinationBuffers[index].mDataByteSize = UInt32(byteCount)
        }

        return pcmBuffer
    }

    nonisolated private static func defaultRouteMatches(
        device: AudioHardwareDevice,
        defaultInputDevice: AudioHardwareDevice?
    ) -> Bool {
        guard let defaultInputDevice else {
            return false
        }

        return defaultInputDevice.uid == device.uid
    }

    private static func selectedRecordingDevice(
        defaults: UserDefaults = .standard
    ) -> AudioHardwareDevice? {
        let availableDevices = AudioInputDeviceManager.allInputDevices()
        let strategyRawValue = defaults.string(forKey: MacPreferences.audioDeviceSelectionStrategy) ?? ""
        let preferredUID = defaults.string(forKey: MacPreferences.preferredAudioInputDeviceUID)

        if strategyRawValue == "manual" {
            if let preferredUID,
               let preferredDevice = availableDevices.first(where: { $0.uid == preferredUID }) {
                return preferredDevice
            }

            return AudioInputDeviceManager.defaultInputDevice()
        }

        if let builtInDevice = availableDevices.first(where: \.isBuiltIn) {
            return builtInDevice
        }

        if let defaultInputDevice = AudioInputDeviceManager.defaultInputDevice(),
           let matchingDefaultDevice = availableDevices.first(where: { $0.uid == defaultInputDevice.uid }) {
            return matchingDefaultDevice
        }

        return availableDevices.max(by: { $0.automaticSelectionPriority < $1.automaticSelectionPriority })
    }

    private static func describe(candidate: InputDeviceCandidate) -> String {
        "\(candidate.reason.rawValue):\(candidate.device?.name ?? "systemDefault")"
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
