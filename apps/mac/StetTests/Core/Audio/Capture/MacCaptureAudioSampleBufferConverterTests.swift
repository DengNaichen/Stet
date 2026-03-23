#if os(macOS)
import AVFoundation
import CoreMedia
import Testing

@testable import Stet

@Suite("Mac Capture Audio Sample Buffer Converter")
struct MacCaptureAudioSampleBufferConverterTests {
    @Test func pcmBufferFromValidSampleBufferCopiesSamples() throws {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 1,
                interleaved: false
            )
        )

        let expectedSamples: [Float] = [0.125, -0.25, 0.5, 0.875]
        let sampleBuffer = try makeSampleBuffer(
            format: format,
            samples: expectedSamples
        )
        let pcmBuffer = try MacCaptureAudioSampleBufferConverter.pcmBuffer(from: sampleBuffer)

        #expect(pcmBuffer.frameLength == expectedSamples.count)
        #expect(pcmBuffer.format.sampleRate == 48_000)
        #expect(pcmBuffer.format.channelCount == 1)

        let copiedSamples = try #require(pcmBuffer.floatChannelData?[0])
        for (index, expected) in expectedSamples.enumerated() {
            #expect(abs(copiedSamples[index] - expected) < 0.0001)
        }
    }

    @Test func pcmBufferFromSampleBufferWithoutFormatDescriptionThrows() throws {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 1,
                interleaved: false
            )
        )

        let sampleBuffer = try makeSampleBuffer(
            format: format,
            samples: [0.125, 0.25],
            includeFormatDescription: false
        )

        #expect {
            try MacCaptureAudioSampleBufferConverter.pcmBuffer(from: sampleBuffer)
        } throws: { error in
            guard case CaptureError.unsupportedSampleBufferFormat = error else {
                return false
            }
            return true
        }
    }

    private func makeSampleBuffer(
        format: AVAudioFormat,
        samples: [Float],
        includeFormatDescription: Bool = true
    ) throws -> CMSampleBuffer {
        let formatDescription = includeFormatDescription ? try makeFormatDescription(for: format) : nil
        let dataLength = samples.count * MemoryLayout<Float>.size
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataLength,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataLength,
            flags: CMBlockBufferFlags(kCMBlockBufferAssureMemoryNowFlag),
            blockBufferOut: &blockBuffer
        )

        guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
            throw CaptureError.failedToCreatePCMBuffer
        }

        let replaceStatus = samples.withUnsafeBytes { rawBuffer -> OSStatus in
            let baseAddress = rawBuffer.baseAddress!
            return CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: dataLength
            )
        }

        guard replaceStatus == kCMBlockBufferNoErr else {
            throw CaptureError.failedToCreatePCMBuffer
        }

        var sampleTiming = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(format.sampleRate)),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )

        var sampleSize = MemoryLayout<Float>.size
        var sampleBuffer: CMSampleBuffer?
        let sampleBufferStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: includeFormatDescription ? formatDescription : nil,
            sampleCount: samples.count,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &sampleTiming,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleBufferStatus == noErr, let sampleBuffer else {
            throw CaptureError.failedToCreatePCMBuffer
        }

        return sampleBuffer
    }

    private func makeFormatDescription(for format: AVAudioFormat) throws -> CMAudioFormatDescription {
        var formatDescription: CMAudioFormatDescription?
        var asbd = format.streamDescription.pointee
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        guard status == noErr, let formatDescription else {
            throw CaptureError.unsupportedSampleBufferFormat
        }

        return formatDescription
    }
}
#endif
