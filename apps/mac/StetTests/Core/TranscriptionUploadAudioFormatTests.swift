import AVFoundation
import Testing

@testable import Stet

@Suite("Transcription Upload Audio Format")
struct TranscriptionUploadAudioFormatTests {
    #if os(macOS)
    @Test func macFormatTargetsWhisperFriendlyPCMShape() throws {
        let format = try #require(TranscriptionUploadAudioFormat.makeMacOutputFormat())

        #expect(format.sampleRate == 16_000)
        #expect(format.channelCount == 1)
        #expect(format.settings[AVFormatIDKey] as? UInt32 == kAudioFormatLinearPCM)
        #expect(format.settings[AVLinearPCMBitDepthKey] as? UInt32 == 16)
        #expect((format.settings[AVLinearPCMIsFloatKey] as? Bool) == false)
        #expect((format.settings[AVLinearPCMIsNonInterleaved] as? Bool) == false)
    }

    @Test func macConvertedFrameCapacityScalesToTargetSampleRate() {
        let capacity = TranscriptionUploadAudioFormat.macConvertedFrameCapacity(
            for: 4_096,
            inputSampleRate: 48_000
        )

        #expect(capacity >= 1_366)
        #expect(capacity <= 1_500)
    }
    #endif

    @Test func iosRecorderSettingsRemainAACMono() {
        let settings = TranscriptionUploadAudioFormat.iOSRecorderSettings

        #expect((settings[AVFormatIDKey] as? NSNumber)?.uint32Value == kAudioFormatMPEG4AAC)
        #expect((settings[AVSampleRateKey] as? NSNumber)?.doubleValue == 44_100)
        #expect((settings[AVNumberOfChannelsKey] as? NSNumber)?.intValue == 1)
    }
}
