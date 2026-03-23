import AVFoundation
import Testing

@testable import Stet

@Suite("Transcription Upload Audio Format")
struct TranscriptionUploadAudioFormatTests {
    #if os(macOS)
    @Test func macFormatTargetsWhisperFriendlyPCMShape() throws {
        let format = try #require(TranscriptionUploadAudioFormat.makeMacOutputFormat())

        #expect(TranscriptionUploadAudioFormat.macFileExtension == "wav")
        #expect(TranscriptionUploadAudioFormat.macSampleRate == 16_000)
        #expect(TranscriptionUploadAudioFormat.macChannelCount == 1)
        #expect(TranscriptionUploadAudioFormat.macLinearPCMBitDepth == 16)
        #expect(format.sampleRate == 16_000)
        #expect(format.channelCount == 1)
        #expect(format.commonFormat == .pcmFormatInt16)
        #expect(format.isInterleaved == true)
        #expect((format.settings[AVFormatIDKey] as? NSNumber)?.uint32Value == kAudioFormatLinearPCM)
        #expect((format.settings[AVLinearPCMBitDepthKey] as? NSNumber)?.uint32Value == 16)
        #expect((format.settings[AVLinearPCMIsFloatKey] as? Bool) == false)
    }
    #endif

    @Test func iosRecorderSettingsRemainAACMono() {
        let settings = TranscriptionUploadAudioFormat.iOSRecorderSettings

        #expect((settings[AVFormatIDKey] as? NSNumber)?.uint32Value == kAudioFormatMPEG4AAC)
        #expect((settings[AVSampleRateKey] as? NSNumber)?.doubleValue == 44_100)
        #expect((settings[AVNumberOfChannelsKey] as? NSNumber)?.intValue == 1)
    }
}
