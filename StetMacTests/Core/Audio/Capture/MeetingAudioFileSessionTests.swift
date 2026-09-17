#if os(macOS)
    import AVFoundation
    import Foundation
    import Testing

    @testable import Stet

    @Suite("Meeting Audio Files")
    struct MeetingAudioFileSessionTests {
        @Test func twentyMinuteTimelinePreservesBothTracksThroughTheLastBuffer() throws {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let session = try MeetingAudioFileSession(directory: directory, startTime: 100)
            let microphone = try tone(hertz: 400, rate: 44_100, duration: 1)
            let system = try tone(hertz: 900, rate: 48_000, duration: 1, channels: 2)
            for second in 0..<1_200 {
                try session.append(system, source: .system, hostTime: 100 + Double(second))
                try session.append(microphone, source: .microphone, hostTime: 100 + Double(second))
            }
            let result = try session.finish(at: 1_300)
            #expect(result.failureMessage == nil)
            #expect(result.duration == 1_200)
            let file = try AVAudioFile(forReading: result.audioURL, commonFormat: .pcmFormatFloat32, interleaved: false)
            #expect(file.length == 19_200_000)
            file.framePosition = file.length - 16_000
            let tail = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_000))
            try file.read(into: tail)
            let channel = try #require(tail.floatChannelData?[0])
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(tail.frameLength)))
            #expect(samples.count == 16_000)
            #expect(toneAmplitude(samples, hertz: 400, from: 0, count: 16_000) > 0.15)
            #expect(toneAmplitude(samples, hertz: 900, from: 0, count: 16_000) > 0.15)
        }

        @Test func stopDrainsOwnedBuffersFromBothSources() async throws {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let sink = try MeetingAudioRecordingSink(directory: directory, startTime: 100, onFailure: { _ in })
            for index in 0..<20 {
                let buffer = try tone(hertz: 500, rate: 48_000, duration: 0.1)
                sink.receive(buffer, source: .microphone, hostTime: 100 + Double(index) / 10)
                sink.receive(buffer, source: .system, hostTime: 100 + Double(index) / 10)
                // Capture frameworks may reuse the borrowed buffer immediately after their callback.
                buffer.floatChannelData?[0].update(repeating: 0, count: Int(buffer.frameLength))
            }
            let result = try await sink.finish(at: 102)
            let samples = try read(result.audioURL)
            #expect(result.failureMessage == nil)
            #expect(samples.count == 32_000)
            #expect(toneAmplitude(samples, hertz: 500, from: 28_000, count: 3_200) > 0.3)
        }

        @Test func errorDuringStopDrainIsSavedAsRecordingFailure() async throws {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let sink = try MeetingAudioRecordingSink(directory: directory, startTime: 100, onFailure: { _ in })
            let buffer = try tone(hertz: 500, rate: 16_000, duration: 0.1)
            sink.receive(buffer, source: .microphone, hostTime: 100)
            sink.receive(buffer, source: .system, hostTime: .nan)
            let result = try await sink.finish(at: 100.1)
            #expect(result.failureMessage?.contains("invalid audio timing") == true)
            #expect(try read(result.audioURL).count == 1_600)
        }

        @Test func bothSourcesSurviveResamplingAndDifferentCallbackOrder() throws {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let session = try MeetingAudioFileSession(directory: directory, startTime: 100)
            // System playback begins after recording, and its callback arrives first.
            try session.append(
                tone(hertz: 1_000, rate: 48_000, duration: 0.5, channels: 2), source: .system, hostTime: 100.25)
            try session.append(tone(hertz: 400, rate: 44_100, duration: 1), source: .microphone, hostTime: 100)
            let result = try session.finish(at: 101)

            let mix = try read(result.audioURL)
            let mic = try read(directory.appendingPathComponent("microphone.wav"))
            let system = try read(directory.appendingPathComponent("system.wav"))
            #expect(result.failureMessage == nil)
            #expect(mix.count == 16_000)
            #expect(mic.count == mix.count)
            #expect(system.count == mix.count)
            #expect(energy(system, from: 0, to: 3_500) == 0)
            #expect(energy(system, from: 4_500, to: 11_000) > 0.05)
            #expect(energy(system, from: 12_500, to: 16_000) == 0)
            #expect(toneAmplitude(mix, hertz: 400, from: 5_000, count: 4_800) > 0.15)
            #expect(toneAmplitude(mix, hertz: 1_000, from: 5_000, count: 4_800) > 0.15)
        }

        @Test func microphoneOnlyWithSilentSystemIsSuccessful() throws {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let session = try MeetingAudioFileSession(directory: directory, startTime: 10)
            try session.append(tone(hertz: 300, rate: 16_000, duration: 0.1), source: .microphone, hostTime: 10)
            let result = try session.finish(at: 10.1)
            #expect(result.failureMessage == nil)
            #expect(try read(result.audioURL).count == 1_600)
            #expect(try energy(read(result.audioURL), from: 0, to: 1_600) > 0.01)
            #expect(try read(directory.appendingPathComponent("system.wav")).allSatisfy { $0 == 0 })
        }

        @Test func alreadyPlayingSystemAndMicrophoneAreBothRecordedFromStart() throws {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let session = try MeetingAudioFileSession(directory: directory, startTime: 10)
            try session.append(tone(hertz: 300, rate: 16_000, duration: 0.1), source: .microphone, hostTime: 10)
            try session.append(tone(hertz: 900, rate: 16_000, duration: 0.1), source: .system, hostTime: 10)
            let result = try session.finish(at: 10.1)
            let samples = try read(result.audioURL)
            #expect(toneAmplitude(samples, hertz: 300, from: 0, count: 1_600) > 0.15)
            #expect(toneAmplitude(samples, hertz: 900, from: 0, count: 1_600) > 0.15)
        }

        @Test func formatChangeAndGapRetainTimelineAndPreviouslyRecordedAudio() throws {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let session = try MeetingAudioFileSession(directory: directory, startTime: 10)
            try session.append(tone(hertz: 300, rate: 16_000, duration: 0.1), source: .microphone, hostTime: 10)
            try session.append(tone(hertz: 900, rate: 48_000, duration: 0.1), source: .system, hostTime: 10)
            try session.append(tone(hertz: 900, rate: 44_100, duration: 0.1), source: .system, hostTime: 10.2)
            let result = try session.finish(at: 10.3, failure: "The microphone disconnected.")
            let samples = try read(directory.appendingPathComponent("system.wav"))
            #expect(samples.count == 4_800)
            #expect(energy(samples, from: 0, to: 1_500) > 0.05)
            #expect(energy(samples, from: 1_700, to: 3_100) == 0)
            #expect(energy(samples, from: 3_400, to: 4_700) > 0.05)
            #expect(result.failureMessage == "The microphone disconnected.")
            #expect(try read(result.audioURL).count == 4_800)
            let manifest = try String(contentsOf: directory.appendingPathComponent("capture.json"), encoding: .utf8)
            #expect(manifest.contains("formatChanged"))
            #expect(manifest.contains("failed"))
        }

        @Test func missingMicrophoneIsNotReportedAsSuccessful() throws {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let session = try MeetingAudioFileSession(directory: directory, startTime: 10)
            try session.append(tone(hertz: 900, rate: 16_000, duration: 0.1), source: .system, hostTime: 10)
            let result = try session.finish(at: 10.1)
            #expect(result.failureMessage?.contains("microphone") == true)
            #expect(try read(result.audioURL).count == 1_600)
        }

        @Test func mixWriteFailureClosesAndPreservesSourceFiles() throws {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let session = try MeetingAudioFileSession(directory: directory, startTime: 10)
            try session.append(tone(hertz: 300, rate: 48_000, duration: 0.1), source: .microphone, hostTime: 10)
            // A directory at the output URL deterministically rejects creation of the mixed WAV.
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("audio.wav"), withIntermediateDirectories: true)
            #expect(throws: (any Error).self) { try session.finish(at: 10.1) }
            #expect(try read(directory.appendingPathComponent("microphone.wav")).count == 1_600)
            let data = try Data(contentsOf: directory.appendingPathComponent("capture.json"))
            let manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(manifest["status"] as? String == "failed")
        }

        @Test func oversizedBacklogStopsCaptureAndKeepsAcceptedAudio() async throws {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let sink = try MeetingAudioRecordingSink(directory: directory, startTime: 10, onFailure: { _ in })
            let buffer = try tone(hertz: 300, rate: 16_000, duration: 0.1)
            sink.receive(buffer, source: .microphone, hostTime: 10)
            let tooLarge = try #require(AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: 2_100_000))
            tooLarge.frameLength = tooLarge.frameCapacity
            sink.receive(tooLarge, source: .system, hostTime: 10)
            let result = try await sink.finish(at: 10.1)
            #expect(result.failureMessage?.contains("saved fast enough") == true)
            #expect(try read(result.audioURL).count == 1_600)
        }

        private func temporaryDirectory() -> URL {
            FileManager.default.temporaryDirectory.appendingPathComponent("stet-meeting-test-\(UUID())")
        }

        private func tone(hertz: Double, rate: Double, duration: Double, channels: AVAudioChannelCount = 1) throws
            -> AVAudioPCMBuffer
        {
            let format = try #require(
                AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false)
            )
            let count = AVAudioFrameCount((rate * duration).rounded())
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count))
            buffer.frameLength = count
            let data = try #require(buffer.floatChannelData)
            for channel in 0..<Int(channels) {
                for index in 0..<Int(count) {
                    data[channel][index] = Float(0.4 * sin(2 * .pi * hertz * Double(index) / rate))
                }
            }
            return buffer
        }

        private func read(_ url: URL) throws -> [Float] {
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = try #require(
                AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let channel = try #require(buffer.floatChannelData?[0])
            return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }

        private func energy(_ samples: [Float], from start: Int, to end: Int) -> Double {
            samples[start..<end].reduce(0) { $0 + Double($1 * $1) } / Double(end - start)
        }

        private func toneAmplitude(_ samples: [Float], hertz: Double, from start: Int, count: Int) -> Double {
            var sine = 0.0
            var cosine = 0.0
            for index in start..<(start + count) {
                let phase = 2 * .pi * hertz * Double(index) / 16_000
                sine += Double(samples[index]) * sin(phase)
                cosine += Double(samples[index]) * cos(phase)
            }
            return 2 * hypot(sine, cosine) / Double(count)
        }
    }
#endif
