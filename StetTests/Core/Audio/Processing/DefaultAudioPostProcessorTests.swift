import AVFoundation
import Testing

@testable import Stet

@Suite("Default Audio Post Processor", .serialized)
@MainActor
struct DefaultAudioPostProcessorTests {
    @Test func silenceOnlyCaptureIsDiscarded() async throws {
        let fileURL = try Self.makePCMFileURL(
            samples: Array(repeating: 0, count: 16_000)
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try await Self.makePostProcessor(interactionSoundsEnabled: false).processAudioFile(
            at: fileURL,
            duration: 1
        )

        #expect(result.shouldDiscardAsNoSpeech)
        #expect(result.url == fileURL)
    }

    @Test func stationaryNoiseOnlyCaptureIsDiscarded() async throws {
        let fileURL = try Self.makePCMFileURL(samples: Self.makeStationaryNoiseSamples())
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try await Self.makePostProcessor(interactionSoundsEnabled: false).processAudioFile(
            at: fileURL,
            duration: 1
        )

        #expect(result.shouldDiscardAsNoSpeech)
        #expect(result.url == fileURL)
    }

    @Test func keyboardLikeClickTrackIsDiscarded() async throws {
        let fileURL = try Self.makePCMFileURL(samples: Self.makeKeyboardClickSamples())
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try await Self.makePostProcessor(interactionSoundsEnabled: false).processAudioFile(
            at: fileURL,
            duration: 1
        )

        #expect(result.shouldDiscardAsNoSpeech)
        #expect(result.url == fileURL)
    }

    @Test func keyboardLikeClicksMixedWithStationaryNoiseAreDiscarded() async throws {
        let samples = Self.mixSamples(
            Self.makeStationaryNoiseSamples(),
            Self.makeKeyboardClickSamples()
        )
        let fileURL = try Self.makePCMFileURL(samples: samples)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try await Self.makePostProcessor(interactionSoundsEnabled: false).processAudioFile(
            at: fileURL,
            duration: 1
        )

        #expect(result.shouldDiscardAsNoSpeech)
        #expect(result.url == fileURL)
    }

    @Test func quietSpeechCaptureIsRewrittenAndPreserved() async throws {
        let quietSpeech = Self.makeSpeechLikeSamples(amplitude: 1_050)
        let fileURL = try Self.makePCMFileURL(samples: quietSpeech)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try await Self.makePostProcessor(interactionSoundsEnabled: false).processAudioFile(
            at: fileURL,
            duration: 1
        )
        let outputURL = result.url
        let cleanupURLs = result.cleanupURLs
        defer {
            for url in cleanupURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        #expect(!result.shouldDiscardAsNoSpeech)
        #expect(outputURL != fileURL)
        #expect(Set(cleanupURLs) == Set([fileURL, outputURL]))

        let inputSummary = try Self.audioSummary(at: fileURL)
        let outputSummary = try Self.audioSummary(at: outputURL)
        #expect(inputSummary.sampleRate == outputSummary.sampleRate)
        #expect(inputSummary.channelCount == outputSummary.channelCount)
        #expect(abs(inputSummary.duration - outputSummary.duration) < 0.0001)
        #expect(outputSummary.rms > inputSummary.rms)
    }

    @Test func stationaryNoiseWithSpeechIsRewrittenAndPreserved() async throws {
        let samples = Self.mixSamples(
            Self.makeStationaryNoiseSamples(),
            Self.makeSpeechLikeSamples(amplitude: 1_200)
        )
        let fileURL = try Self.makePCMFileURL(samples: samples)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try await Self.makePostProcessor(interactionSoundsEnabled: false).processAudioFile(
            at: fileURL,
            duration: 1
        )
        let outputURL = result.url
        let cleanupURLs = result.cleanupURLs
        defer {
            for url in cleanupURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        #expect(!result.shouldDiscardAsNoSpeech)
        #expect(outputURL != fileURL)
        #expect(Set(cleanupURLs) == Set([fileURL, outputURL]))

        let inputSummary = try Self.audioSummary(at: fileURL)
        let outputSummary = try Self.audioSummary(at: outputURL)
        #expect(outputSummary.rms > inputSummary.rms)
    }

    @Test func loudSpeechCaptureIsPassedThroughWithoutFurtherAmplification() async throws {
        let loudSpeech = Self.makeSpeechLikeSamples(amplitude: 12_500)
        let fileURL = try Self.makePCMFileURL(samples: loudSpeech)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try await Self.makePostProcessor(interactionSoundsEnabled: false).processAudioFile(
            at: fileURL,
            duration: 1
        )

        #expect(!result.shouldDiscardAsNoSpeech)
        #expect(result.url == fileURL)
    }

    @Test func captureWithLongPauseIsTrimmed() async throws {
        let spoken = Self.makeSpeechLikeSamples(amplitude: 12_500)
        let longPause = Array(repeating: Int16(0), count: 32_000)
        let samples = spoken + longPause + spoken

        let fileURL = try Self.makePCMFileURL(samples: samples)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try await Self.makePostProcessor(interactionSoundsEnabled: false).processAudioFile(
            at: fileURL,
            duration: 4
        )
        let outputURL = result.url
        let cleanupURLs = result.cleanupURLs
        let reportedDuration = result.duration
        defer {
            for url in cleanupURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        #expect(!result.shouldDiscardAsNoSpeech)
        #expect(outputURL != fileURL)

        let inputSummary = try Self.audioSummary(at: fileURL)
        let outputSummary = try Self.audioSummary(at: outputURL)
        #expect(outputSummary.duration < (inputSummary.duration - 1.0))
        #expect(outputSummary.duration > 1.8)
        if let reportedDuration {
            #expect(abs(reportedDuration - outputSummary.duration) < 0.01)
        }
    }

    private static func makePCMFileURL(samples: [Int16]) throws -> URL {
        let fileURL = TestSupport.temporaryFileURL(ext: "wav")
        let outputFormat = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: TranscriptionUploadAudioFormat.macSampleRate,
                channels: TranscriptionUploadAudioFormat.macChannelCount,
                interleaved: false
            )
        )
        let audioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: outputFormat.settings,
            commonFormat: outputFormat.commonFormat,
            interleaved: outputFormat.isInterleaved
        )

        let chunkSize = 4_096
        for startIndex in stride(from: 0, to: samples.count, by: chunkSize) {
            let endIndex = min(startIndex + chunkSize, samples.count)
            let frameCount = endIndex - startIndex
            let buffer = try #require(
                AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: AVAudioFrameCount(frameCount)
                )
            )
            buffer.frameLength = AVAudioFrameCount(frameCount)
            let channelData = try #require(buffer.int16ChannelData)

            for sampleIndex in 0..<frameCount {
                channelData[0][sampleIndex] = samples[startIndex + sampleIndex]
            }

            try audioFile.write(from: buffer)
        }

        return fileURL
    }

    private static func makeSpeechLikeSamples(amplitude: Int16) -> [Int16] {
        let sampleRate = 16_000.0
        let leadingSilence = Array(repeating: Int16(0), count: 2_400)
        let trailingSilence = Array(repeating: Int16(0), count: 2_400)
        let spokenSampleCount = 11_200
        let baseFrequency = 170.0

        let speech = (0..<spokenSampleCount).map { index -> Int16 in
            let time = Double(index) / sampleRate
            let envelope = 0.55 + 0.45 * sin(2 * .pi * 2.8 * time)
            let glide = baseFrequency + 35.0 * sin(2 * .pi * 1.3 * time)
            let voicedSample =
                sin(2 * .pi * glide * time) + 0.45 * sin(2 * .pi * glide * 2.0 * time) + 0.18
                * sin(2 * .pi * glide * 3.0 * time)
            let fricativeTexture = 0.08 * sin(2 * .pi * 2_300 * time)
            let sample = Double(amplitude) * envelope * (0.72 * voicedSample + fricativeTexture)
            return Int16(max(Double(Int16.min), min(sample, Double(Int16.max))))
        }

        return leadingSilence + speech + trailingSilence
    }

    private static func makeStationaryNoiseSamples() -> [Int16] {
        let sampleRate = 16_000.0
        let sampleCount = 16_000
        var state: UInt32 = 0x1234_ABCD

        return (0..<sampleCount).map { index -> Int16 in
            let time = Double(index) / sampleRate
            state = 1_664_525 &* state &+ 1_013_904_223
            let whiteNoise = Double(Int32(bitPattern: state)) / Double(Int32.max)
            let hum =
                sin(2 * .pi * 90.0 * time) + 0.55 * sin(2 * .pi * 180.0 * time) + 0.2 * sin(2 * .pi * 1_700.0 * time)
            let sample = 180.0 * hum + 35.0 * whiteNoise
            return Int16(max(Double(Int16.min), min(sample, Double(Int16.max))))
        }
    }

    private static func makeKeyboardClickSamples() -> [Int16] {
        let sampleRate = 16_000.0
        let sampleCount = 16_000
        let clickCenters = [2_200, 4_900, 7_300, 10_200, 13_100]
        let clickWidth = 120

        return (0..<sampleCount).map { index -> Int16 in
            var sample = 0.0

            for center in clickCenters {
                let distance = abs(index - center)
                guard distance <= clickWidth else { continue }

                let normalizedDistance = Double(distance) / Double(clickWidth)
                let envelope = pow(max(0, 1 - normalizedDistance), 2.2)
                let time = Double(index) / sampleRate
                let click =
                    sin(2 * .pi * 2_800.0 * time) + 0.75 * sin(2 * .pi * 4_600.0 * time) + 0.35
                    * sin(2 * .pi * 6_100.0 * time)
                sample += 650.0 * envelope * click
            }

            return Int16(max(Double(Int16.min), min(sample, Double(Int16.max))))
        }
    }

    private static func mixSamples(_ lhs: [Int16], _ rhs: [Int16]) -> [Int16] {
        let sampleCount = max(lhs.count, rhs.count)
        return (0..<sampleCount).map { index in
            let left = index < lhs.count ? Int(lhs[index]) : 0
            let right = index < rhs.count ? Int(rhs[index]) : 0
            return Int16(
                max(
                    Int(Int16.min),
                    min(left + right, Int(Int16.max))
                )
            )
        }
    }

    private struct AudioSummary {
        let sampleRate: Double
        let channelCount: AVAudioChannelCount
        let duration: TimeInterval
        let rms: Double
    }

    private static func audioSummary(at fileURL: URL) throws -> AudioSummary {
        let audioFile = try AVAudioFile(forReading: fileURL)
        let samples = try Self.readSamples(from: fileURL)

        let sampleSum = samples.reduce(0.0) { partialResult, sample in
            let value = Double(sample)
            return partialResult + value * value
        }
        let rms = samples.isEmpty ? 0 : sqrt(sampleSum / Double(samples.count))

        return AudioSummary(
            sampleRate: audioFile.fileFormat.sampleRate,
            channelCount: audioFile.fileFormat.channelCount,
            duration: TimeInterval(audioFile.length) / audioFile.fileFormat.sampleRate,
            rms: rms
        )
    }

    private static func readSamples(from fileURL: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: fileURL)
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard frameCount > 0 else { return [] }

        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount))
        try audioFile.read(into: buffer)
        guard let channelData = buffer.floatChannelData else { return [] }

        let length = Int(buffer.frameLength)
        return (0..<length).map { channelData[0][$0] }
    }

    private static func makePostProcessor(
        interactionSoundsEnabled: Bool = true,
        interactionSoundPreset: InteractionSoundPreset = .soft
    ) -> DefaultAudioPostProcessor {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(interactionSoundsEnabled, forKey: MacPreferences.interactionSoundsEnabled)
        defaults.set(interactionSoundPreset.rawValue, forKey: MacPreferences.interactionSoundPreset)
        let settingsStore = DictationSettingsStore(
            defaults: defaults,
            secretStore: TestSecretStore()
        )
        return DefaultAudioPostProcessor(settingsStore: settingsStore)
    }

}
