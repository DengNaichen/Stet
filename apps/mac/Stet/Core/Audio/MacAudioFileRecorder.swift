#if os(macOS)
@preconcurrency import AVFoundation
import Foundation

final class MacAudioFileRecordingSession {
    private let lock = NSLock()
    let outputFormat: AVAudioFormat
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

final class MacAudioFileRecorder {
    private enum Configuration {
        static let tapBufferSize: AVAudioFrameCount = 1_024
    }

    private let firstBufferLock = NSLock()
    private let stateLock = NSLock()
    private let audioEngine: AVAudioEngine
    private let audioLevelHandler: @Sendable (Double) -> Void
    private let onFirstBufferWritten: @Sendable () -> Void
    private var isTapInstalled = false
    private var activeSession: MacAudioFileRecordingSession?
    private var hasWrittenFirstBuffer = false

    init(
        audioEngine: AVAudioEngine = AVAudioEngine(),
        audioLevelHandler: @escaping @Sendable (Double) -> Void = { _ in },
        onFirstBufferWritten: @escaping @Sendable () -> Void = {}
    ) {
        self.audioEngine = audioEngine
        self.audioLevelHandler = audioLevelHandler
        self.onFirstBufferWritten = onFirstBufferWritten
    }

    func startRecording(to fileURL: URL, outputFormat: AVAudioFormat) throws {
        precondition(currentSession() == nil, "MacAudioFileRecorder is already recording.")

        let inputNode = audioEngine.inputNode
        let reportedInputFormat = inputNode.outputFormat(forBus: 0)
        let recordingFile = try AVAudioFile(
            forWriting: fileURL,
            settings: outputFormat.settings,
            commonFormat: outputFormat.commonFormat,
            interleaved: outputFormat.isInterleaved
        )
        let recordingSession = MacAudioFileRecordingSession(
            recordingFile: recordingFile,
            outputFormat: outputFormat
        )
        firstBufferLock.lock()
        hasWrittenFirstBuffer = false
        firstBufferLock.unlock()

        AppLogger.info(
            """
            Configuring mac transcription capture. \
            reportedInputSampleRate=\(Int(reportedInputFormat.sampleRate)), \
            reportedInputChannels=\(reportedInputFormat.channelCount), \
            tapBufferSize=\(Configuration.tapBufferSize), \
            outputSampleRate=\(Int(outputFormat.sampleRate)), \
            outputChannels=\(outputFormat.channelCount), \
            fileSampleRate=\(Int(recordingFile.fileFormat.sampleRate)), \
            fileChannels=\(recordingFile.fileFormat.channelCount), \
            fileInterleaved=\(recordingFile.processingFormat.isInterleaved)
            """,
            category: .dictation
        )

        // Prewarm the converter using the reported input format so the first tap callback
        // can focus on conversion and file I/O instead of allocating the converter graph.
        _ = try recordingSession.snapshot(for: reportedInputFormat)

        setCurrentSession(recordingSession)
        installTapIfNeeded(on: inputNode)
        audioEngine.prepare()

        do {
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
        } catch {
            _ = finishSession(keepEngineRunning: false)
            throw error
        }
    }

    func stopRecording(writtenFileAt fileURL: URL) async -> AVAudioFramePosition {
        let writtenFrameCount = finishSession(keepEngineRunning: true)
        await Self.waitForFileToStabilize(at: fileURL)
        return writtenFrameCount
    }

    func cancelRecording() {
        _ = finishSession(keepEngineRunning: true)
    }

    deinit {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioEngine.reset()
    }

    private func installTapIfNeeded(on inputNode: AVAudioInputNode) {
        guard !isTapInstalled else { return }

        inputNode.installTap(onBus: 0, bufferSize: Configuration.tapBufferSize, format: nil) { [weak self] buffer, _ in
            self?.handleIncomingBuffer(buffer)
        }

        isTapInstalled = true
    }

    private func handleIncomingBuffer(_ buffer: AVAudioPCMBuffer) {
        audioLevelHandler(AudioLevelNormalizer.normalizedLevel(from: buffer))

        guard let session = currentSession() else {
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

            try snapshot.recordingFile.write(from: convertedBuffer)
            session.recordWrite(frameLength: convertedBuffer.frameLength)
            firstBufferLock.lock()
            let shouldRecordFirstBuffer = !hasWrittenFirstBuffer
            if shouldRecordFirstBuffer {
                hasWrittenFirstBuffer = true
            }
            firstBufferLock.unlock()

            if shouldRecordFirstBuffer {
                onFirstBufferWritten()
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

    private func finishSession(keepEngineRunning: Bool) -> AVAudioFramePosition {
        let session = clearCurrentSession()
        let writtenFrameCount = session?.totalWrittenFrames() ?? 0
        session?.close()

        if !keepEngineRunning, audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.reset()
        }

        firstBufferLock.lock()
        hasWrittenFirstBuffer = false
        firstBufferLock.unlock()
        return writtenFrameCount
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
