import AVFoundation
import Foundation

enum TranscriptionUploadAudioFormat {
    #if os(macOS)
    nonisolated static let macSampleRate: Double = 16_000
    nonisolated static let macChannelCount: AVAudioChannelCount = 1
    nonisolated static let macLinearPCMBitDepth: UInt32 = 16
    nonisolated static let macFileExtension = "wav"

    nonisolated static var macOutputSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: macSampleRate,
            AVNumberOfChannelsKey: macChannelCount,
            AVLinearPCMBitDepthKey: macLinearPCMBitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    nonisolated static func makeMacOutputFormat() -> AVAudioFormat? {
        AVAudioFormat(settings: macOutputSettings)
    }

    nonisolated static func macConvertedFrameCapacity(
        for inputFrameCount: AVAudioFrameCount,
        inputSampleRate: Double
    ) -> AVAudioFrameCount {
        guard inputFrameCount > 0, inputSampleRate > 0, inputSampleRate.isFinite else {
            return 0
        }

        let ratio = macSampleRate / inputSampleRate
        let scaledFrameCount = ceil(Double(inputFrameCount) * ratio)
        return max(AVAudioFrameCount(scaledFrameCount) + 32, 32)
    }
    #endif

    nonisolated static let iOSFileExtension = "m4a"

    nonisolated static var iOSRecorderSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
    }
}
