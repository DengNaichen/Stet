import AVFoundation
import Testing

@testable import Stet

@Suite("Linear PCM Conversion")
struct LinearPCMConversionTests {
    @Test func convertedFrameCapacityScalesToTargetSampleRate() {
        let capacity = LinearPCMConversion.convertedFrameCapacity(
            for: 4_096,
            inputSampleRate: 48_000,
            outputSampleRate: 16_000
        )

        #expect(capacity >= 1_366)
        #expect(capacity <= 1_500)
    }

    @Test func converterDownmixesStereoInputToMonoOutput() throws {
        let inputFormat = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 2,
                interleaved: false
            )
        )
        let outputFormat = try #require(TranscriptionUploadAudioFormat.makeMacOutputFormat())
        let converter = try #require(
            LinearPCMConversion.makeConverter(
                from: inputFormat,
                to: outputFormat
            )
        )

        #expect(converter.inputFormat.channelCount == 2)
        #expect(converter.outputFormat.channelCount == 1)
        #expect(converter.downmix == true)
    }
}
