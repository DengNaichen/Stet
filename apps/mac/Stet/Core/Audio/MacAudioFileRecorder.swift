#if os(macOS)
@preconcurrency import AVFoundation
import Foundation

struct MacAudioFileRecordingOutcome: Sendable {
    let writtenFrameCount: AVAudioFramePosition
    let didCommitSpeech: Bool

    static let empty = Self(writtenFrameCount: 0, didCommitSpeech: false)
}

final class MacAudioFileRecordingSession {
    struct BufferIngestionResult: Sendable {
        let processedAudioLevel: Double
        let didWriteCommittedFrames: Bool
        let didDetectEndpoint: Bool
    }

    private let lock = NSLock()
    let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var converterInputFormatSignature: String?
    private var recordingFile: AVAudioFile?
    private var frontend: StreamingSpeechCaptureFrontend?
    private var pendingInputSamples: [Int16] = []
    private var writtenFrameCount: AVAudioFramePosition = 0
    private var didCommitSpeech = false
    private var droppedBufferLogCount = 0

    init(recordingFile: AVAudioFile, outputFormat: AVAudioFormat) throws {
        self.recordingFile = recordingFile
        self.outputFormat = outputFormat
        self.frontend = try StreamingSpeechCaptureFrontend()
        self.pendingInputSamples.reserveCapacity(StreamingSpeechCaptureFrontend.Configuration.balanced.frameSize * 2)
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

        guard let recordingFile,
              let frontend,
              let channelData = buffer.int16ChannelData else {
            return nil
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return BufferIngestionResult(
                processedAudioLevel: 0.08,
                didWriteCommittedFrames: false,
                didDetectEndpoint: false
            )
        }

        let inputSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        pendingInputSamples.append(contentsOf: inputSamples)

        var committedSamples: [Int16] = []
        committedSamples.reserveCapacity(pendingInputSamples.count)
        var processedAudioLevel = 0.08
        var didDetectEndpoint = false
        let frameSize = StreamingSpeechCaptureFrontend.Configuration.balanced.frameSize

        while pendingInputSamples.count >= frameSize {
            let frameSamples = Array(pendingInputSamples.prefix(frameSize))
            pendingInputSamples.removeFirst(frameSize)

            let processResult = try frontend.process(frameSamples: frameSamples)
            processedAudioLevel = max(
                processedAudioLevel,
                Self.normalizedLevel(for: processResult.processedSamples)
            )
            for committedFrame in processResult.committedFrames {
                committedSamples.append(contentsOf: committedFrame)
            }
            didDetectEndpoint = didDetectEndpoint || processResult.didDetectEndpoint
        }

        let didWriteCommittedFrames = !committedSamples.isEmpty
        if didWriteCommittedFrames {
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(committedSamples.count)
            ), let outputChannelData = outputBuffer.int16ChannelData else {
                throw LinearPCMConversion.ConversionError.outputBufferCreationFailed
            }

            outputBuffer.frameLength = AVAudioFrameCount(committedSamples.count)
            for index in committedSamples.indices {
                outputChannelData[0][index] = committedSamples[index]
            }

            try recordingFile.write(from: outputBuffer)
            writtenFrameCount += AVAudioFramePosition(committedSamples.count)
            didCommitSpeech = true
        }

        return BufferIngestionResult(
            processedAudioLevel: processedAudioLevel,
            didWriteCommittedFrames: didWriteCommittedFrames,
            didDetectEndpoint: didDetectEndpoint
        )
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
        frontend?.activateRecordingWindow()
        lock.unlock()
    }

    func recordWrite(frameLength: AVAudioFrameCount) {
        lock.lock()
        writtenFrameCount += AVAudioFramePosition(frameLength)
        lock.unlock()
    }

    func close() {
        lock.lock()
        converter = nil
        converterInputFormatSignature = nil
        recordingFile = nil
        frontend = nil
        pendingInputSamples.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    func totalWrittenFrames() -> AVAudioFramePosition {
        lock.lock()
        defer { lock.unlock() }
        return writtenFrameCount
    }

    func recordingOutcome() -> MacAudioFileRecordingOutcome {
        lock.lock()
        defer { lock.unlock() }
        return MacAudioFileRecordingOutcome(
            writtenFrameCount: writtenFrameCount,
            didCommitSpeech: didCommitSpeech
        )
    }

    private static func formatSignature(_ format: AVAudioFormat) -> String {
        "\(String(describing: format.commonFormat)):\(Int(format.sampleRate)):\(format.channelCount):\(format.isInterleaved)"
    }

    private static func normalizedLevel(for samples: [Int16]) -> Double {
        guard !samples.isEmpty else { return 0.08 }
        let peak = samples.reduce(0.0) { partialResult, sample in
            max(partialResult, abs(Double(sample)) / Double(Int16.max))
        }
        guard peak.isFinite else { return 0.08 }
        return max(0.08, min(peak, 1))
    }
}

final class MacAudioFileRecorder {
    private enum Configuration {
        static let tapBufferSize: AVAudioFrameCount = 1_024
    }

    private let firstBufferLock = NSLock()
    private let stateLock = NSLock()
    private let audioEngine: AVAudioEngine
    private let audioLevelHandler: @Sendable (Double) -> Void
    private let onFirstCommittedBufferWritten: @Sendable () -> Void
    private let onEndpointDetected: @Sendable () -> Void
    private var isTapInstalled = false
    private var activeSession: MacAudioFileRecordingSession?
    private var hasWrittenFirstCommittedBuffer = false

    init(
        audioEngine: AVAudioEngine = AVAudioEngine(),
        audioLevelHandler: @escaping @Sendable (Double) -> Void = { _ in },
        onFirstCommittedBufferWritten: @escaping @Sendable () -> Void = {},
        onEndpointDetected: @escaping @Sendable () -> Void = {}
    ) {
        self.audioEngine = audioEngine
        self.audioLevelHandler = audioLevelHandler
        self.onFirstCommittedBufferWritten = onFirstCommittedBufferWritten
        self.onEndpointDetected = onEndpointDetected
    }

    func startRecording(
        to fileURL: URL,
        outputFormat: AVAudioFormat
    ) throws {
        precondition(currentSession() == nil, "MacAudioFileRecorder is already recording.")

        let inputNode = audioEngine.inputNode
        let recordingFile = try AVAudioFile(
            forWriting: fileURL,
            settings: outputFormat.settings,
            commonFormat: outputFormat.commonFormat,
            interleaved: outputFormat.isInterleaved
        )
        let recordingSession = try MacAudioFileRecordingSession(
            recordingFile: recordingFile,
            outputFormat: outputFormat
        )
        firstBufferLock.lock()
        hasWrittenFirstCommittedBuffer = false
        firstBufferLock.unlock()

        do {
            try startRecordingSession(recordingSession, on: inputNode, outputFormat: outputFormat)
        } catch {
            _ = finishSession()
            throw error
        }
    }

    func activateRecordingWindow() {
        currentSession()?.activateRecordingWindow()
    }

    func stopRecording(writtenFileAt fileURL: URL) async -> MacAudioFileRecordingOutcome {
        let outcome = finishSession()
        await Self.waitForFileToStabilize(at: fileURL)
        return outcome
    }

    func cancelRecording() {
        _ = finishSession()
    }

    deinit {
        _ = finishSession()
    }

    private func startRecordingSession(
        _ recordingSession: MacAudioFileRecordingSession,
        on inputNode: AVAudioInputNode,
        outputFormat: AVAudioFormat
    ) throws {
        let tapFormat = inputNode.outputFormat(forBus: 0)
        _ = try recordingSession.snapshot(for: tapFormat)
        setCurrentSession(recordingSession)

        try startEngine(on: inputNode, tapFormat: tapFormat)

        AppLogger.info(
            """
            Configuring mac transcription capture. \
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

    private func startEngine(
        on inputNode: AVAudioInputNode,
        tapFormat: AVAudioFormat
    ) throws {
        installTapIfNeeded(on: inputNode, format: tapFormat)
        audioEngine.prepare()

        do {
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
        } catch {
            tearDownEngine()
            AppLogger.error(
                "Failed to start the macOS capture engine. error=\(error.localizedDescription)",
                category: .dictation
            )
            throw SpeechServiceError.failedToStart
        }
    }

    private func installTapIfNeeded(on inputNode: AVAudioInputNode, format tapFormat: AVAudioFormat) {
        guard !isTapInstalled else { return }

        inputNode.installTap(onBus: 0, bufferSize: Configuration.tapBufferSize, format: tapFormat) { [weak self] buffer, when in
            self?.handleIncomingBuffer(buffer, when: when)
        }

        isTapInstalled = true
    }

    private func handleIncomingBuffer(_ buffer: AVAudioPCMBuffer, when: AVAudioTime) {
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

            audioLevelHandler(ingestionResult.processedAudioLevel)
            emitFirstCommittedBufferIfNeeded(didWriteCommittedFrames: ingestionResult.didWriteCommittedFrames)

            if ingestionResult.didDetectEndpoint {
                onEndpointDetected()
            }
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

    private func emitFirstCommittedBufferIfNeeded(didWriteCommittedFrames: Bool) {
        guard didWriteCommittedFrames else { return }

        firstBufferLock.lock()
        let shouldEmit = !hasWrittenFirstCommittedBuffer
        if shouldEmit {
            hasWrittenFirstCommittedBuffer = true
        }
        firstBufferLock.unlock()

        if shouldEmit {
            onFirstCommittedBufferWritten()
        }
    }

    private func finishSession() -> MacAudioFileRecordingOutcome {
        let session = clearCurrentSession()
        let outcome = session?.recordingOutcome() ?? .empty
        session?.close()
        tearDownEngine()

        firstBufferLock.lock()
        hasWrittenFirstCommittedBuffer = false
        firstBufferLock.unlock()
        return outcome
    }

    private func tearDownEngine() {
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()
    }

    private func currentSession() -> MacAudioFileRecordingSession? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeSession
    }

    private func setCurrentSession(_ session: MacAudioFileRecordingSession) {
        stateLock.lock()
        activeSession = session
        stateLock.unlock()
    }

    private func clearCurrentSession() -> MacAudioFileRecordingSession? {
        stateLock.lock()
        let session = activeSession
        activeSession = nil
        stateLock.unlock()
        return session
    }

    static func waitForFileToStabilize(at fileURL: URL) async {
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
