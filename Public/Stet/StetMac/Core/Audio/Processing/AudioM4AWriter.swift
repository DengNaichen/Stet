@preconcurrency import AVFoundation
import AudioToolbox
import Foundation

enum AudioM4AWriter {
    static func writeAACM4A(
        samples: [Float],
        sampleRate: Double,
        filePrefix: String,
        bitRate: Int = 48_000
    ) throws -> URL {
        guard !samples.isEmpty, sampleRate > 0 else {
            throw AudioM4AWriterError.invalidInput
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filePrefix)-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let processingFormat = try requireFormat(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        )

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
        ]

        let audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: processingFormat.commonFormat,
            interleaved: processingFormat.isInterleaved
        )

        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: processingFormat,
                frameCapacity: AVAudioFrameCount(samples.count)
            )
        else {
            throw AudioM4AWriterError.unableToCreateOutputBuffer
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channelData = buffer.floatChannelData else {
            throw AudioM4AWriterError.unableToAccessOutputChannelData
        }

        for index in samples.indices {
            channelData[0][index] = min(max(samples[index], -1), 1)
        }

        try audioFile.write(from: buffer)
        return outputURL
    }

    private static func requireFormat(_ format: AVAudioFormat?) throws -> AVAudioFormat {
        guard let format else {
            throw AudioM4AWriterError.unableToCreateProcessingFormat
        }
        return format
    }
}

enum AudioM4AWriterError: Error {
    case invalidInput
    case unableToCreateProcessingFormat
    case unableToCreateOutputBuffer
    case unableToAccessOutputChannelData
}
