#if os(macOS)
    @preconcurrency import AVFoundation
    import Foundation

    nonisolated enum MeetingAudioSource: String, Codable, Sendable, CaseIterable {
        case microphone
        case system
    }

    nonisolated enum MeetingRecordingError: Error, LocalizedError, Sendable {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message): message
            }
        }
    }

    nonisolated struct MeetingAudioRecordingResult: Sendable {
        let audioURL: URL
        let sampleCount: Int
        let duration: TimeInterval
        let failureMessage: String?
    }

    /// Owned by the recording writer queue. Source timestamps use the host clock, in seconds.
    nonisolated final class MeetingAudioFileSession {
        static let sampleRate = 16_000.0
        private static let blockSize: AVAudioFrameCount = 4_096
        private let directory: URL
        private let startTime: TimeInterval
        private let format: AVAudioFormat
        private var tracks: [MeetingAudioSource: Track] = [:]
        private var discontinuities: [Discontinuity] = []
        private var finished = false

        private struct Track {
            var file: AVAudioFile
            var inputFormat: AVAudioFormat?
            var converter: AVAudioConverter?
            var capturedFrames = 0
            var writtenFrames: Int64 = 0
            var pendingFrames = 0.0
            var nextInputTime: Double?
        }

        private struct Discontinuity: Codable {
            var source: MeetingAudioSource
            var atSeconds: Double
            var offsetSeconds: Double
            var reason: String
        }

        private struct Manifest: Codable {
            var status: String
            var sampleRate: Double
            var durationSeconds: Double
            var microphoneFrames: Int
            var systemFrames: Int
            var failureMessage: String?
            var discontinuities: [Discontinuity]
        }

        init(directory: URL, startTime: TimeInterval) throws {
            self.directory = directory
            self.startTime = startTime
            guard
                let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false
                )
            else { throw MeetingRecordingError.failed("Could not create the meeting audio format.") }
            self.format = format
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for source in MeetingAudioSource.allCases {
                tracks[source] = Track(file: try makeFile(at: sourceURL(source)))
            }
            try writeManifest(status: "recording", duration: 0, failure: nil)
        }

        func append(_ input: AVAudioPCMBuffer, source: MeetingAudioSource, hostTime: TimeInterval) throws {
            guard !finished else { return }
            guard hostTime.isFinite, input.format.sampleRate.isFinite, input.format.sampleRate > 0 else {
                throw MeetingRecordingError.failed("The \(source.rawValue) supplied invalid audio timing.")
            }
            guard input.frameLength > 0, var track = tracks[source] else { return }
            let relativeTime = hostTime - startTime
            // A bad clock must not cause hours of zero-fill or overflow a sample index.
            guard abs(relativeTime) < 24 * 60 * 60 else {
                throw MeetingRecordingError.failed("The \(source.rawValue) audio clock is out of range.")
            }
            let changedFormat = track.inputFormat != input.format
            let hasGap = track.nextInputTime.map { abs(hostTime - $0) > 0.02 } ?? false
            if changedFormat || hasGap {
                try flush(&track)
                if track.inputFormat != nil {
                    discontinuities.append(
                        Discontinuity(
                            source: source, atSeconds: relativeTime,
                            offsetSeconds: hostTime - (track.nextInputTime ?? hostTime),
                            reason: changedFormat ? "formatChanged" : "timestampGap"
                        )
                    )
                }
                track.inputFormat = input.format
                track.converter = LinearPCMConversion.makeConverter(from: input.format, to: format)
            }
            guard let converter = track.converter else {
                throw MeetingRecordingError.failed("Could not convert \(source.rawValue) audio.")
            }
            let position = Int64((relativeTime * Self.sampleRate - track.pendingFrames).rounded())
            let buffer = try LinearPCMConversion.convert(input, using: converter, outputFormat: format)
            track.pendingFrames = max(
                0,
                track.pendingFrames
                    + Double(input.frameLength) * Self.sampleRate / input.format.sampleRate - Double(buffer.frameLength)
            )
            track.nextInputTime = hostTime + Double(input.frameLength) / input.format.sampleRate
            try write(buffer, at: position, to: &track)
            tracks[source] = track
        }

        func finish(at hostTime: TimeInterval, failure: String? = nil) throws -> MeetingAudioRecordingResult {
            guard !finished else { throw MeetingRecordingError.failed("The recording has already been finalized.") }
            finished = true
            var duration = 0.0
            var microphoneFrames = tracks[.microphone]?.capturedFrames ?? 0
            var systemFrames = tracks[.system]?.capturedFrames ?? 0
            do {
                let elapsed = hostTime - startTime
                guard elapsed.isFinite, elapsed >= 0, elapsed < 24 * 60 * 60 else {
                    throw MeetingRecordingError.failed("The meeting recording duration is invalid.")
                }
                for source in MeetingAudioSource.allCases {
                    if var track = tracks[source] {
                        try flush(&track)
                        tracks[source] = track
                    }
                }
                let length = max(
                    AVAudioFramePosition((elapsed * Self.sampleRate).rounded()),
                    tracks.values.map { $0.writtenFrames }.max() ?? 0
                )
                duration = Double(length) / Self.sampleRate
                let captureFailure =
                    failure
                    ?? (tracks[.microphone]?.capturedFrames == 0
                        ? "No microphone audio was received. Check the selected input and microphone permission." : nil)
                for source in MeetingAudioSource.allCases {
                    if var track = tracks[source] {
                        try pad(&track, to: length)
                        tracks[source] = track
                    }
                }
                microphoneFrames = tracks[.microphone]?.capturedFrames ?? 0
                systemFrames = tracks[.system]?.capturedFrames ?? 0
                // Releasing the writers finalizes WAV headers before they are reopened for mixing.
                tracks.removeAll()
                let audioURL = directory.appendingPathComponent("audio.wav")
                try mix(to: audioURL, length: length)
                try writeManifest(
                    status: captureFailure == nil ? "recorded" : "failed",
                    duration: duration, failure: captureFailure,
                    microphoneFrames: microphoneFrames, systemFrames: systemFrames
                )
                return MeetingAudioRecordingResult(
                    audioURL: audioURL, sampleCount: Int(length), duration: duration,
                    failureMessage: captureFailure
                )
            } catch {
                // Close source files even if flushing, padding, or mixing fails (for example, disk full).
                tracks.removeAll()
                try? writeManifest(
                    status: "failed", duration: duration, failure: error.localizedDescription,
                    microphoneFrames: microphoneFrames, systemFrames: systemFrames
                )
                throw error
            }
        }

        private func sourceURL(_ source: MeetingAudioSource) -> URL {
            directory.appendingPathComponent("\(source.rawValue).wav")
        }

        private func makeFile(at url: URL) throws -> AVAudioFile {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: Self.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            return try AVAudioFile(
                forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        }

        private func write(_ buffer: AVAudioPCMBuffer, at position: Int64, to track: inout Track) throws {
            try pad(&track, to: max(0, position))
            let skip = max(0, track.writtenFrames - position)
            guard skip < Int64(buffer.frameLength) else { return }
            let count = Int(buffer.frameLength) - Int(skip)
            guard let samples = buffer.floatChannelData?[0],
                let slice = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                let destination = slice.floatChannelData?[0]
            else { throw MeetingRecordingError.failed("Could not allocate meeting audio.") }
            slice.frameLength = AVAudioFrameCount(count)
            destination.update(from: samples.advanced(by: Int(skip)), count: count)
            try track.file.write(from: slice)
            track.writtenFrames += Int64(count)
            track.capturedFrames += count
        }

        private func flush(_ track: inout Track) throws {
            guard let converter = track.converter, let endTime = track.nextInputTime else { return }
            let position = Int64(((endTime - startTime) * Self.sampleRate - track.pendingFrames).rounded())
            guard
                let tail = AVAudioPCMBuffer(
                    pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(track.pendingFrames)) + Self.blockSize
                )
            else { throw MeetingRecordingError.failed("Could not finalize audio conversion.") }
            var error: NSError?
            let status = converter.convert(to: tail, error: &error) { _, inputStatus in
                inputStatus.pointee = .endOfStream
                return nil
            }
            if let error { throw error }
            guard status != .error else { throw MeetingRecordingError.failed("Could not finalize audio conversion.") }
            // The resampler may emit filter ringing beyond the actual captured duration.
            tail.frameLength = min(tail.frameLength, AVAudioFrameCount(ceil(track.pendingFrames)))
            try write(tail, at: position, to: &track)
            track.pendingFrames = 0
            track.converter = nil
        }

        private func pad(_ track: inout Track, to position: Int64) throws {
            guard track.writtenFrames < position else { return }
            guard let zeros = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.blockSize),
                let samples = zeros.floatChannelData?[0]
            else { throw MeetingRecordingError.failed("Could not allocate audio padding.") }
            samples.update(repeating: 0, count: Int(Self.blockSize))
            while track.writtenFrames < position {
                zeros.frameLength = AVAudioFrameCount(min(Int64(Self.blockSize), position - track.writtenFrames))
                try track.file.write(from: zeros)
                track.writtenFrames += Int64(zeros.frameLength)
            }
        }

        private func mix(to url: URL, length: AVAudioFramePosition) throws {
            let mic = try AVAudioFile(
                forReading: sourceURL(.microphone), commonFormat: .pcmFormatFloat32, interleaved: false)
            let system = try AVAudioFile(
                forReading: sourceURL(.system), commonFormat: .pcmFormatFloat32, interleaved: false)
            let output = try makeFile(at: url)
            guard let left = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.blockSize),
                let right = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.blockSize),
                let mixed = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.blockSize),
                let a = left.floatChannelData?[0], let b = right.floatChannelData?[0],
                let destination = mixed.floatChannelData?[0]
            else { throw MeetingRecordingError.failed("Could not allocate the meeting mix buffers.") }
            var writtenFrames: Int64 = 0
            while writtenFrames < length {
                let count = AVAudioFrameCount(min(Int64(Self.blockSize), length - writtenFrames))
                try mic.read(into: left, frameCount: count)
                try system.read(into: right, frameCount: count)
                guard left.frameLength == count, right.frameLength == count else {
                    throw MeetingRecordingError.failed(
                        "A meeting source file ended unexpectedly. Source recordings were kept.")
                }
                mixed.frameLength = count
                for index in 0..<Int(count) { destination[index] = (a[index] + b[index]) * 0.5 }
                try output.write(from: mixed)
                writtenFrames += Int64(count)
            }
        }

        private func writeManifest(
            status: String, duration: Double, failure: String?, microphoneFrames: Int = 0, systemFrames: Int = 0
        ) throws {
            let manifest = Manifest(
                status: status, sampleRate: Self.sampleRate, durationSeconds: duration,
                microphoneFrames: microphoneFrames, systemFrames: systemFrames,
                failureMessage: failure, discontinuities: discontinuities
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: directory.appendingPathComponent("capture.json"), options: .atomic)
        }
    }

#endif
