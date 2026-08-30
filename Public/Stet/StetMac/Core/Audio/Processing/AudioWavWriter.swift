@preconcurrency import AVFoundation
import Foundation

enum AudioWavWriter {
    nonisolated static func writePCM16MonoWav(
        samples: [Float],
        filePrefix: String
    ) throws -> URL {
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: TranscriptionUploadAudioFormat.macSampleRate,
                channels: TranscriptionUploadAudioFormat.macChannelCount,
                interleaved: false
            )
        else {
            throw AudioWavWriterError.unableToCreateOutputFormat
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filePrefix)-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: outputFormat.commonFormat,
            interleaved: outputFormat.isInterleaved
        )

        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(samples.count)
            )
        else {
            throw AudioWavWriterError.unableToCreateOutputBuffer
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channelData = buffer.int16ChannelData else {
            throw AudioWavWriterError.unableToAccessOutputChannelData
        }

        for index in samples.indices {
            let clamped = min(max(Double(samples[index]), -1), 1)
            let scaled = (clamped * Double(Int16.max)).rounded()
            channelData[0][index] = Int16(max(Double(Int16.min), min(scaled, Double(Int16.max))))
        }

        try audioFile.write(from: buffer)
        return outputURL
    }
}

enum AudioWavWriterError: Error {
    case unableToCreateOutputFormat
    case unableToCreateOutputBuffer
    case unableToAccessOutputChannelData
}
