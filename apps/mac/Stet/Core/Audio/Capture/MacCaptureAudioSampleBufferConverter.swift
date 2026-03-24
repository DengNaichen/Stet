#if os(macOS)
    @preconcurrency import AVFoundation
    import CoreMedia
    import Foundation

    enum MacCaptureAudioSampleBufferConverter {
        nonisolated static func pcmBuffer(
            from sampleBuffer: CMSampleBuffer
        ) throws -> AVAudioPCMBuffer {
            guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
                let streamDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
            else {
                throw CaptureError.unsupportedSampleBufferFormat
            }

            var streamDescription = streamDescriptionPointer.pointee
            guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
                throw CaptureError.unsupportedSampleBufferFormat
            }

            let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
            guard
                let pcmBuffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: frameCount
                )
            else {
                throw CaptureError.failedToCreatePCMBuffer
            }
            pcmBuffer.frameLength = frameCount

            var audioBufferListSize = Int(
                MemoryLayout<AudioBufferList>.size + max(Int(format.channelCount) - 1, 0)
                    * MemoryLayout<AudioBuffer>.size
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
                    let destinationData = destination.mData
                else {
                    throw CaptureError.unsupportedSampleBufferFormat
                }

                let byteCount = Int(min(source.mDataByteSize, destination.mDataByteSize))
                memcpy(destinationData, sourceData, byteCount)
                destinationBuffers[index].mDataByteSize = UInt32(byteCount)
            }

            return pcmBuffer
        }
    }
#endif
