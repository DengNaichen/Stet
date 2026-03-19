#if os(macOS)
@preconcurrency import AudioToolbox
import Foundation

final class MacAudioQueueRecorder: @unchecked Sendable {
    private enum Configuration {
        static let bufferDurationSeconds = 0.02
        static let minimumBufferByteSize: UInt32 = 1_024
        static let bufferCount = 3
    }

    private struct State {
        var queue: AudioQueueRef?
        var audioFile: AudioFileID?
        var outputFormat: AudioStreamBasicDescription?
        var isRecording = false
        var currentPacket: Int64 = 0
        var hasWrittenFirstBuffer = false
    }

    private let stateLock = NSLock()
    private let onFirstBufferWritten: @Sendable () -> Void
    private var state = State()

    init(onFirstBufferWritten: @escaping @Sendable () -> Void = {}) {
        self.onFirstBufferWritten = onFirstBufferWritten
    }

    func startRecording(
        to fileURL: URL,
        outputFormat: AudioStreamBasicDescription,
        inputDeviceUID: String? = nil,
        fileType: AudioFileTypeID = kAudioFileCAFType
    ) throws {
        precondition(!isRecording, "MacAudioQueueRecorder is already recording.")
        Task {
            await DictationRuntimeProbe.shared.markAction("audioQueue.startRecording")
        }

        var outputFormat = outputFormat
        var queue: AudioQueueRef?
        let queueStatus = AudioQueueNewInput(
            &outputFormat,
            Self.inputCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            nil,
            0,
            &queue
        )

        guard queueStatus == noErr, let queue else {
            throw Self.makeStartError(status: queueStatus)
        }

        if let inputDeviceUID {
            var currentDeviceUID = inputDeviceUID as CFString
            let currentDeviceStatus = AudioQueueSetProperty(
                queue,
                kAudioQueueProperty_CurrentDevice,
                &currentDeviceUID,
                UInt32(MemoryLayout<CFString>.size)
            )
            guard currentDeviceStatus == noErr else {
                AudioQueueDispose(queue, true)
                throw Self.makeStartError(status: currentDeviceStatus)
            }
        }

        var meteringEnabled: UInt32 = 1
        let meteringStatus = AudioQueueSetProperty(
            queue,
            kAudioQueueProperty_EnableLevelMetering,
            &meteringEnabled,
            UInt32(MemoryLayout.size(ofValue: meteringEnabled))
        )
        guard meteringStatus == noErr else {
            AudioQueueDispose(queue, true)
            throw Self.makeStartError(status: meteringStatus)
        }

        var audioFile: AudioFileID?
        let fileStatus = AudioFileCreateWithURL(
            fileURL as CFURL,
            fileType,
            &outputFormat,
            AudioFileFlags.eraseFile,
            &audioFile
        )
        guard fileStatus == noErr, let audioFile else {
            AudioQueueDispose(queue, true)
            throw Self.makeStartError(status: fileStatus)
        }

        let bufferByteSize = Self.inputBufferByteSize(for: outputFormat)
        for _ in 0..<Configuration.bufferCount {
            var buffer: AudioQueueBufferRef?
            let allocationStatus = AudioQueueAllocateBuffer(queue, bufferByteSize, &buffer)
            guard allocationStatus == noErr, let buffer else {
                AudioFileClose(audioFile)
                AudioQueueDispose(queue, true)
                throw Self.makeStartError(status: allocationStatus)
            }

            buffer.pointee.mAudioDataByteSize = bufferByteSize
            let enqueueStatus = AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
            guard enqueueStatus == noErr else {
                AudioFileClose(audioFile)
                AudioQueueDispose(queue, true)
                throw Self.makeStartError(status: enqueueStatus)
            }
        }

        stateLock.lock()
        state.queue = queue
        state.audioFile = audioFile
        state.outputFormat = outputFormat
        state.isRecording = true
        state.currentPacket = 0
        state.hasWrittenFirstBuffer = false
        stateLock.unlock()

        let startStatus = AudioQueueStart(queue, nil)
        guard startStatus == noErr else {
            Task {
                await DictationRuntimeProbe.shared.markCaptureStartError("audioQueueStartFailed status=\(startStatus)")
            }
            _ = finishRecording()
            throw Self.makeStartError(status: startStatus)
        }

        AppLogger.info(
            """
            Configured mac audio queue recorder. \
            sampleRate=\(Int(outputFormat.mSampleRate)), \
            channels=\(outputFormat.mChannelsPerFrame), \
            bytesPerFrame=\(outputFormat.mBytesPerFrame), \
            bufferByteSize=\(bufferByteSize), \
            bufferCount=\(Configuration.bufferCount)
            """,
            category: .dictation
        )
    }

    func stopRecording() {
        Task {
            await DictationRuntimeProbe.shared.markCaptureStopped()
        }
        _ = finishRecording()
    }

    func cancelRecording() {
        Task {
            await DictationRuntimeProbe.shared.markCaptureCancelled()
        }
        _ = finishRecording()
    }

    func currentAveragePowerLevel() -> Float? {
        stateLock.lock()
        guard let queue = state.queue, state.isRecording else {
            stateLock.unlock()
            return nil
        }
        stateLock.unlock()

        var meterState = AudioQueueLevelMeterState()
        var propertySize = UInt32(MemoryLayout<AudioQueueLevelMeterState>.size)
        let status = AudioQueueGetProperty(
            queue,
            kAudioQueueProperty_CurrentLevelMeterDB,
            &meterState,
            &propertySize
        )

        guard status == noErr else {
            return nil
        }

        return meterState.mAveragePower
    }

    private func finishRecording() -> (queue: AudioQueueRef?, audioFile: AudioFileID?) {
        stateLock.lock()
        state.isRecording = false
        let queue = state.queue
        let audioFile = state.audioFile
        state.queue = nil
        state.audioFile = nil
        state.outputFormat = nil
        state.currentPacket = 0
        state.hasWrittenFirstBuffer = false
        stateLock.unlock()

        if let queue {
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
        }

        if let audioFile {
            AudioFileClose(audioFile)
        }

        return (queue, audioFile)
    }

    private func handleInputBuffer(
        queue: AudioQueueRef,
        buffer: AudioQueueBufferRef,
        inNumPackets: UInt32,
        packetDescriptions: UnsafePointer<AudioStreamPacketDescription>?
    ) {
        var callbackAudioFile: AudioFileID?
        var callbackOutputFormat: AudioStreamBasicDescription?
        var currentPacket: Int64 = 0
        var shouldWrite = false

        stateLock.lock()
        if state.isRecording,
           let audioFile = state.audioFile,
           let outputFormat = state.outputFormat {
            callbackAudioFile = audioFile
            callbackOutputFormat = outputFormat
            currentPacket = state.currentPacket
            shouldWrite = true
        }
        stateLock.unlock()

        guard shouldWrite,
              let audioFile = callbackAudioFile,
              let outputFormat = callbackOutputFormat else {
            return
        }

        let packetCount: UInt32
        if inNumPackets > 0 {
            packetCount = inNumPackets
        } else if outputFormat.mBytesPerPacket > 0 {
            packetCount = buffer.pointee.mAudioDataByteSize / outputFormat.mBytesPerPacket
        } else {
            packetCount = 0
        }

        guard packetCount > 0 else {
            _ = AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
            return
        }

        var packetCountToWrite = packetCount
        let byteCount = buffer.pointee.mAudioDataByteSize
        let writeStatus = AudioFileWritePackets(
            audioFile,
            false,
            byteCount,
            packetDescriptions,
            currentPacket,
            &packetCountToWrite,
            buffer.pointee.mAudioData
        )

        guard writeStatus == noErr else {
            AppLogger.warning(
                "Audio queue write failed. status=\(writeStatus)",
                category: .dictation
            )
            _ = AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
            return
        }

        var shouldEmitFirstBuffer = false
        stateLock.lock()
        if state.isRecording {
            state.currentPacket += Int64(packetCountToWrite)
            if !state.hasWrittenFirstBuffer {
                state.hasWrittenFirstBuffer = true
                shouldEmitFirstBuffer = true
            }
        }
        stateLock.unlock()

        if shouldEmitFirstBuffer {
            onFirstBufferWritten()
        }

        let enqueueStatus = AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
        if enqueueStatus != noErr {
            AppLogger.warning(
                "Audio queue re-enqueue failed. status=\(enqueueStatus)",
                category: .dictation
            )
        }
    }

    private var isRecording: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state.isRecording
    }

    private static let inputCallback: AudioQueueInputCallback = { userData, queue, buffer, _, inNumPackets, packetDescriptions in
        guard let userData else { return }
        let recorder = Unmanaged<MacAudioQueueRecorder>.fromOpaque(userData).takeUnretainedValue()
        recorder.handleInputBuffer(
            queue: queue,
            buffer: buffer,
            inNumPackets: inNumPackets,
            packetDescriptions: packetDescriptions
        )
    }

    private static func inputBufferByteSize(for format: AudioStreamBasicDescription) -> UInt32 {
        let desiredByteSize = UInt32(
            ceil(format.mSampleRate * Configuration.bufferDurationSeconds)
        ) * format.mBytesPerFrame
        return max(desiredByteSize, Configuration.minimumBufferByteSize)
    }

    private static func makeStartError(status: OSStatus) -> SpeechServiceError {
        AppLogger.error("Audio queue start failed. status=\(status)", category: .dictation)
        return .failedToStart
    }

    deinit {
        _ = finishRecording()
    }
}
#endif
