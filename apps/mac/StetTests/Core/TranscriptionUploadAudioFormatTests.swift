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
        #expect(format.commonFormat == .pcmFormatInt16)
        #expect(format.isInterleaved == true)
        #expect((format.settings[AVFormatIDKey] as? NSNumber)?.uint32Value == kAudioFormatLinearPCM)
        #expect((format.settings[AVLinearPCMBitDepthKey] as? NSNumber)?.uint32Value == 16)
        #expect((format.settings[AVLinearPCMIsFloatKey] as? Bool) == false)
    }

    @Test func macConvertedFrameCapacityScalesToTargetSampleRate() {
        let capacity = TranscriptionUploadAudioFormat.macConvertedFrameCapacity(
            for: 4_096,
            inputSampleRate: 48_000
        )

        #expect(capacity >= 1_366)
        #expect(capacity <= 1_500)
    }

    @Test func macConverterDownmixesStereoInputToMonoOutput() throws {
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
            TranscriptionUploadAudioFormat.makeMacConverter(
                from: inputFormat,
                to: outputFormat
            )
        )

        #expect(converter.inputFormat.channelCount == 2)
        #expect(converter.outputFormat.channelCount == 1)
        #expect(converter.downmix == true)
    }

    @Test func macFormatProducesReadablePCMFileAfterWriterCloses() throws {
        let format = try #require(TranscriptionUploadAudioFormat.makeMacOutputFormat())
        let fileURL = TestSupport.temporaryFileURL(ext: "wav")
        try? FileManager.default.removeItem(at: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            let audioFile = try AVAudioFile(
                forWriting: fileURL,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            let frameCount: AVAudioFrameCount = 1_600
            let buffer = try #require(
                AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
            )
            buffer.frameLength = frameCount

            let channelData = try #require(buffer.int16ChannelData)
            for index in 0..<Int(frameCount) {
                channelData[0][index] = Int16((index % 200) - 100)
            }

            try audioFile.write(from: buffer)
        }

        let reopenedFile = try AVAudioFile(forReading: fileURL)
        #expect(reopenedFile.length == 1_600)
        #expect(reopenedFile.fileFormat.sampleRate == 16_000)
    }
    #endif

    @Test func iosRecorderSettingsRemainAACMono() {
        let settings = TranscriptionUploadAudioFormat.iOSRecorderSettings

        #expect((settings[AVFormatIDKey] as? NSNumber)?.uint32Value == kAudioFormatMPEG4AAC)
        #expect((settings[AVSampleRateKey] as? NSNumber)?.doubleValue == 44_100)
        #expect((settings[AVNumberOfChannelsKey] as? NSNumber)?.intValue == 1)
    }
}
