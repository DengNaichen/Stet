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
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: macSampleRate,
            channels: macChannelCount,
            interleaved: true
        )
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
