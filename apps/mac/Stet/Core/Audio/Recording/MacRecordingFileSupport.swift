#if os(macOS)
@preconcurrency import AVFoundation
import Foundation

struct MacAudioFileRecordingOutcome: Sendable {
    let writtenFrameCount: AVAudioFramePosition
    let didWriteAudio: Bool
    let captureDiagnosticsSummary: String?

    nonisolated static let empty = Self(
        writtenFrameCount: 0,
        didWriteAudio: false,
        captureDiagnosticsSummary: nil
    )
}

nonisolated final class MacAudioFileRecordingSession: @unchecked Sendable {
    struct BufferIngestionResult: Sendable {
        let didWriteAudioFrames: Bool
    }

    private enum Configuration {
        nonisolated static let pendingAudioLimitSeconds: Double = 1.5
    }

    private let lock = NSLock()
    nonisolated let outputFormat: AVAudioFormat
    nonisolated private let voiceProcessingEnabled: Bool
    nonisolated private let voiceProcessingFallbackReason: String?
    private var converter: AVAudioConverter?
    private var converterInputFormatSignature: String?
    private var recordingFile: AVAudioFile?
    private var writtenFrameCount: AVAudioFramePosition = 0
    private var didWriteAudio = false
    private var droppedBufferLogCount = 0
    private var hasActivatedCaptureWindow = false
    private var pendingBuffers: [AVAudioPCMBuffer] = []
    private var pendingFrameCount: AVAudioFramePosition = 0

    nonisolated init(
        recordingFile: AVAudioFile,
        outputFormat: AVAudioFormat,
        voiceProcessingEnabled: Bool,
        voiceProcessingFallbackReason: String?
    ) {
        self.recordingFile = recordingFile
        self.outputFormat = outputFormat
        self.voiceProcessingEnabled = voiceProcessingEnabled
        self.voiceProcessingFallbackReason = voiceProcessingFallbackReason
    }

    nonisolated func snapshot(
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

    nonisolated func ingestConvertedBuffer(_ buffer: AVAudioPCMBuffer) throws -> BufferIngestionResult? {
        lock.lock()
        defer { lock.unlock() }

        guard let recordingFile else {
            return nil
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return BufferIngestionResult(didWriteAudioFrames: false)
        }

        guard hasActivatedCaptureWindow else {
            appendPendingBuffer(buffer)
            return BufferIngestionResult(didWriteAudioFrames: false)
        }

        try writeLocked(buffer, to: recordingFile)
        return BufferIngestionResult(didWriteAudioFrames: true)
    }

    nonisolated func shouldLogDroppedBuffer() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard droppedBufferLogCount < 3 else {
            return false
        }

        droppedBufferLogCount += 1
        return true
    }

    nonisolated func activateRecordingWindow() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !hasActivatedCaptureWindow else {
            return
        }

        hasActivatedCaptureWindow = true
        guard let recordingFile else {
            pendingBuffers.removeAll(keepingCapacity: false)
            pendingFrameCount = 0
            return
        }

        for buffer in pendingBuffers {
            try writeLocked(buffer, to: recordingFile)
        }
        pendingBuffers.removeAll(keepingCapacity: false)
        pendingFrameCount = 0
    }

    nonisolated func close() {
        lock.lock()
        converter = nil
        converterInputFormatSignature = nil
        recordingFile = nil
        lock.unlock()
    }

    nonisolated func recordingOutcome() -> MacAudioFileRecordingOutcome {
        lock.lock()
        defer { lock.unlock() }

        let diagnostics =
            """
            didWriteAudio=\(didWriteAudio) activated=\(hasActivatedCaptureWindow) \
            writtenFrames=\(writtenFrameCount) pendingFrames=\(pendingFrameCount) \
            voiceProcessingEnabled=\(voiceProcessingEnabled) \
            fallbackReason=\(voiceProcessingFallbackReason ?? "none")
            """

        return MacAudioFileRecordingOutcome(
            writtenFrameCount: writtenFrameCount,
            didWriteAudio: didWriteAudio,
            captureDiagnosticsSummary: diagnostics
        )
    }

    private nonisolated static func formatSignature(_ format: AVAudioFormat) -> String {
        "\(String(describing: format.commonFormat)):\(Int(format.sampleRate)):\(format.channelCount):\(format.isInterleaved)"
    }

    private nonisolated func appendPendingBuffer(_ buffer: AVAudioPCMBuffer) {
        pendingBuffers.append(buffer)
        pendingFrameCount += AVAudioFramePosition(buffer.frameLength)

        let maximumBufferedFrames = AVAudioFramePosition(
            max(outputFormat.sampleRate * Configuration.pendingAudioLimitSeconds, 0)
        )

        guard maximumBufferedFrames > 0 else {
            pendingBuffers.removeAll(keepingCapacity: false)
            pendingFrameCount = 0
            return
        }

        while pendingFrameCount > maximumBufferedFrames, let oldestBuffer = pendingBuffers.first {
            pendingBuffers.removeFirst()
            pendingFrameCount -= AVAudioFramePosition(oldestBuffer.frameLength)
        }
    }

    private nonisolated func writeLocked(_ buffer: AVAudioPCMBuffer, to recordingFile: AVAudioFile) throws {
        try recordingFile.write(from: buffer)
        writtenFrameCount += AVAudioFramePosition(buffer.frameLength)
        didWriteAudio = true
    }
}
#endif
