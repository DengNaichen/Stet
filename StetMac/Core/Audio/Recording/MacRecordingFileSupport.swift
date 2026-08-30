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

    struct BoundedAudioFrameBuffer: Sendable {
        let capacitySamples: Int64
        private(set) var frames: [AudioCaptureFrame] = []

        init(capacitySamples: Int64) {
            self.capacitySamples = max(capacitySamples, 0)
        }

        mutating func append(_ frame: AudioCaptureFrame) {
            guard !frame.samples.isEmpty, capacitySamples > 0 else { return }
            frames.append(frame)

            var overflow = frames.reduce(Int64(0)) { $0 + Int64($1.samples.count) } - capacitySamples
            while overflow > 0, let first = frames.first {
                let firstCount = Int64(first.samples.count)
                if firstCount <= overflow {
                    frames.removeFirst()
                    overflow -= firstCount
                } else {
                    frames[0] = first.split(at: first.startSample + overflow).after!
                    overflow = 0
                }
            }
        }

        func split(at boundary: Int64) -> (before: [AudioCaptureFrame], after: [AudioCaptureFrame]) {
            var before: [AudioCaptureFrame] = []
            var after: [AudioCaptureFrame] = []

            for frame in frames {
                let split = frame.split(at: boundary)
                if let part = split.before { before.append(part) }
                if let part = split.after { after.append(part) }
            }
            return (before, after)
        }

        mutating func removeAll() {
            frames.removeAll(keepingCapacity: false)
        }
    }

    enum MacNormalizedAudioSamples {
        nonisolated static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
            let count = Int(buffer.frameLength)
            guard count > 0 else { return [] }

            switch buffer.format.commonFormat {
            case .pcmFormatFloat32:
                guard let values = buffer.floatChannelData?[0] else { return [] }
                return Array(UnsafeBufferPointer(start: values, count: count))
            case .pcmFormatInt16:
                guard let values = buffer.int16ChannelData?[0] else { return [] }
                return UnsafeBufferPointer(start: values, count: count).map {
                    Float($0) / Float(Int16.max)
                }
            case .pcmFormatInt32:
                guard let values = buffer.int32ChannelData?[0] else { return [] }
                return UnsafeBufferPointer(start: values, count: count).map {
                    Float($0) / Float(Int32.max)
                }
            default:
                return []
            }
        }
    }

    nonisolated final class MacNormalizedAudioCaptureSession: @unchecked Sendable {
        struct ConversionResult {
            let buffer: AVAudioPCMBuffer
            let didCreateConverter: Bool
        }

        private let lock = NSLock()
        nonisolated let outputFormat: AVAudioFormat
        private var converter: AVAudioConverter?
        private var inputFormatSignature: String?

        nonisolated init(outputFormat: AVAudioFormat) {
            self.outputFormat = outputFormat
        }

        nonisolated func convert(_ input: AVAudioPCMBuffer) throws -> ConversionResult {
            let snapshot = try lock.withLock { () throws -> (AVAudioConverter, Bool) in
                let signature = Self.formatSignature(input.format)
                let didCreate = signature != inputFormatSignature || converter == nil
                if didCreate {
                    guard
                        let converter = LinearPCMConversion.makeConverter(
                            from: input.format,
                            to: outputFormat
                        )
                    else {
                        throw LinearPCMConversion.ConversionError.conversionFailed
                    }
                    self.converter = converter
                    inputFormatSignature = signature
                }
                guard let converter else {
                    throw LinearPCMConversion.ConversionError.conversionFailed
                }
                return (converter, didCreate)
            }

            return try ConversionResult(
                buffer: LinearPCMConversion.convert(
                    input,
                    using: snapshot.0,
                    outputFormat: outputFormat
                ),
                didCreateConverter: snapshot.1
            )
        }

        nonisolated func close() {
            lock.withLock {
                converter = nil
                inputFormatSignature = nil
            }
        }

        private nonisolated static func formatSignature(_ format: AVAudioFormat) -> String {
            "\(String(describing: format.commonFormat)):\(Int(format.sampleRate)):\(format.channelCount):\(format.isInterleaved)"
        }
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
                guard
                    let converter = LinearPCMConversion.makeConverter(
                        from: inputFormat,
                        to: outputFormat
                    )
                else {
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
                let overflow = pendingFrameCount - maximumBufferedFrames
                if AVAudioFramePosition(oldestBuffer.frameLength) <= overflow {
                    pendingBuffers.removeFirst()
                    pendingFrameCount -= AVAudioFramePosition(oldestBuffer.frameLength)
                    continue
                }

                guard let suffix = Self.suffix(of: oldestBuffer, dropping: AVAudioFrameCount(overflow)) else {
                    pendingBuffers.removeFirst()
                    pendingFrameCount -= AVAudioFramePosition(oldestBuffer.frameLength)
                    continue
                }
                pendingBuffers[0] = suffix
                pendingFrameCount -= overflow
            }
        }

        private nonisolated static func suffix(
            of buffer: AVAudioPCMBuffer,
            dropping droppedFrames: AVAudioFrameCount
        ) -> AVAudioPCMBuffer? {
            guard droppedFrames < buffer.frameLength else { return nil }
            let retainedFrames = buffer.frameLength - droppedFrames
            guard
                let suffix = AVAudioPCMBuffer(
                    pcmFormat: buffer.format,
                    frameCapacity: retainedFrames
                )
            else {
                return nil
            }
            suffix.frameLength = retainedFrames

            let sourceBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let destinationBuffers = UnsafeMutableAudioBufferListPointer(suffix.mutableAudioBufferList)
            guard sourceBuffers.count == destinationBuffers.count else { return nil }

            for index in 0..<sourceBuffers.count {
                guard let source = sourceBuffers[index].mData,
                    let destination = destinationBuffers[index].mData,
                    buffer.frameLength > 0
                else {
                    return nil
                }
                let bytesPerFrame = Int(sourceBuffers[index].mDataByteSize) / Int(buffer.frameLength)
                let offset = Int(droppedFrames) * bytesPerFrame
                let byteCount = Int(retainedFrames) * bytesPerFrame
                memcpy(destination, source.advanced(by: offset), byteCount)
                destinationBuffers[index].mDataByteSize = UInt32(byteCount)
            }
            return suffix
        }

        private nonisolated func writeLocked(_ buffer: AVAudioPCMBuffer, to recordingFile: AVAudioFile) throws {
            try recordingFile.write(from: buffer)
            writtenFrameCount += AVAudioFramePosition(buffer.frameLength)
            didWriteAudio = true
        }
    }
#endif
