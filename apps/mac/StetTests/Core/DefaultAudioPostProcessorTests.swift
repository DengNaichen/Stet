import AVFoundation
import Testing

@testable import Stet

@Suite("Default Audio Post Processor")
struct DefaultAudioPostProcessorTests {
    @Test func silenceOnlyCaptureIsDiscarded() throws {
        let fileURL = try Self.makePCMFileURL(
            samples: Array(repeating: 0, count: 16_000)
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try DefaultAudioPostProcessor().processAudioFile(
            at: fileURL,
            duration: 1
        )

        #expect(result.shouldDiscardAsNoSpeech)
        #expect(result.url == fileURL)
    }

    @Test func quietSpeechCaptureIsAmplified() throws {
        let quietSpeech = Self.makeSpeechLikeSamples(amplitude: 450)
        let fileURL = try Self.makePCMFileURL(samples: quietSpeech)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try DefaultAudioPostProcessor().processAudioFile(
            at: fileURL,
            duration: 1
        )
        defer {
            for url in result.cleanupURLs where url != fileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        #expect(!result.shouldDiscardAsNoSpeech)
        #expect(result.url != fileURL)

        let sourcePeak = try Self.peakAmplitude(at: fileURL)
        let normalizedPeak = try Self.peakAmplitude(at: result.url)

        let unwrappedSourcePeak = try #require(sourcePeak)
        let unwrappedNormalizedPeak = try #require(normalizedPeak)

        #expect(unwrappedNormalizedPeak > unwrappedSourcePeak)
        #expect(unwrappedNormalizedPeak <= 0.95)
    }

    private static func makePCMFileURL(samples: [Int16]) throws -> URL {
        let fileURL = TestSupport.temporaryFileURL(ext: "wav")
        let outputFormat = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: TranscriptionUploadAudioFormat.macSampleRate,
                channels: TranscriptionUploadAudioFormat.macChannelCount,
                interleaved: false
            )
        )
        let audioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: outputFormat.settings,
            commonFormat: outputFormat.commonFormat,
            interleaved: outputFormat.isInterleaved
        )

        let chunkSize = 4_096
        for startIndex in stride(from: 0, to: samples.count, by: chunkSize) {
            let endIndex = min(startIndex + chunkSize, samples.count)
            let frameCount = endIndex - startIndex
            let buffer = try #require(
                AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: AVAudioFrameCount(frameCount)
                )
            )
            buffer.frameLength = AVAudioFrameCount(frameCount)
            let channelData = try #require(buffer.int16ChannelData)

            for sampleIndex in 0..<frameCount {
                channelData[0][sampleIndex] = samples[startIndex + sampleIndex]
            }

            try audioFile.write(from: buffer)
        }

        return fileURL
    }

    private static func makeSpeechLikeSamples(amplitude: Int16) -> [Int16] {
        let sampleRate = 16_000.0
        let leadingSilence = Array(repeating: Int16(0), count: 2_400)
        let trailingSilence = Array(repeating: Int16(0), count: 2_400)
        let spokenSampleCount = 11_200
        let frequency = 220.0

        let speech = (0..<spokenSampleCount).map { index -> Int16 in
            let time = Double(index) / sampleRate
            return Int16(Double(amplitude) * sin(2 * .pi * frequency * time))
        }

        return leadingSilence + speech + trailingSilence
    }

    private static func peakAmplitude(at fileURL: URL) throws -> Double? {
        let data = try Data(contentsOf: fileURL)
        guard data.count >= 44 else { return nil }
        guard String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
            return nil
        }

        var offset = 12
        var peak = 0.0

        while offset + 8 <= data.count {
            guard let chunkID = String(data: data[offset..<(offset + 4)], encoding: .ascii) else {
                return nil
            }
            let chunkSize =
                UInt32(data[data.startIndex + offset + 4]) |
                (UInt32(data[data.startIndex + offset + 5]) << 8) |
                (UInt32(data[data.startIndex + offset + 6]) << 16) |
                (UInt32(data[data.startIndex + offset + 7]) << 24)
            let chunkDataOffset = offset + 8
            let chunkDataEnd = chunkDataOffset + Int(chunkSize)
            guard chunkDataEnd <= data.count else { return nil }

            if chunkID == "data" {
                var sampleOffset = chunkDataOffset
                while sampleOffset + 2 <= chunkDataEnd {
                    let sampleBits =
                        UInt16(data[data.startIndex + sampleOffset]) |
                        (UInt16(data[data.startIndex + sampleOffset + 1]) << 8)
                    let sample = Int16(bitPattern: sampleBits)
                    peak = max(peak, abs(Double(sample)) / Double(Int16.max))
                    sampleOffset += 2
                }

                return peak
            }

            offset = chunkDataEnd + Int(chunkSize % 2)
        }

        return nil
    }
}
