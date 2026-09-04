#if os(macOS)
    import AVFoundation
    import Foundation

    struct MeetingAudioWriter {
        private let audioFile: AVAudioFile
        private let format: AVAudioFormat

        init(url: URL) throws {
            guard let format = TranscriptionUploadAudioFormat.makeMacOutputFormat() else {
                throw AudioWavWriterError.unableToCreateOutputFormat
            }
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            self.format = format
            audioFile = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
        }

        func append(_ samples: [Float]) throws {
            guard !samples.isEmpty else { return }
            guard
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: format,
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
        }
    }
#endif
