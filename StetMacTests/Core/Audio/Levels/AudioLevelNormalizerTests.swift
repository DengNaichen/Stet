import AVFoundation
import Testing

@testable import Stet

@Suite("Audio Level Normalizer")
struct AudioLevelNormalizerTests {
    @Test func normalizedLevelUsesMinimumVisibleLevelForEmptyBuffers() throws {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16))
        buffer.frameLength = 0

        #expect(AudioLevelNormalizer.normalizedLevel(from: buffer) == 0.08)
    }

    @Test func normalizedLevelCalculatesRMSForAudioSamples() throws {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4

        let samples = try #require(buffer.floatChannelData?[0])
        samples[0] = 0.25
        samples[1] = 0.25
        samples[2] = 0.25
        samples[3] = 0.25

        let level = AudioLevelNormalizer.normalizedLevel(from: buffer)

        #expect(abs(level - 0.8) < 0.0001)
    }

    @Test func normalizedLevelClampsLoudSignalsToOne() throws {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
        buffer.frameLength = 2

        let samples = try #require(buffer.floatChannelData?[0])
        samples[0] = 1
        samples[1] = 1

        #expect(AudioLevelNormalizer.normalizedLevel(from: buffer) == 1)
    }

    @Test(arguments: [
        (-25.0 as Float, 0.5),
        (-80.0 as Float, 0.08),
        (0.0 as Float, 1.0),
    ])
    func normalizedPowerLevelClampsIntoExpectedRange(_ power: Float, expected: Double) {
        #expect(AudioLevelNormalizer.normalizedPowerLevel(power) == expected)
    }

    @Test func normalizedPowerLevelUsesMinimumVisibleLevelForNonFiniteValues() {
        #expect(AudioLevelNormalizer.normalizedPowerLevel(.infinity) == 0.08)
        #expect(AudioLevelNormalizer.normalizedPowerLevel(.nan) == 0.08)
    }
}
