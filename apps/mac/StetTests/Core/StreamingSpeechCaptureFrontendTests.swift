import Foundation
import Testing

@testable import Stet

@Suite("Streaming Speech Capture Frontend", .serialized)
struct StreamingSpeechCaptureFrontendTests {
    @Test func framesBeforeActivationAreNeverCommitted() throws {
        let promptFrames = Self.makePromptFrames(count: 8)
        let speechFrames = Self.makeSpeechFrames(count: 6, amplitude: 3_000)
        let frontend = try Self.makeFrontend(
            primaryDetections: Array(repeating: true, count: promptFrames.count + speechFrames.count)
        )

        let run = try Self.runFrontend(
            frontend,
            preActivationFrames: promptFrames,
            postActivationFrames: speechFrames
        )

        #expect(run.summary.didCommitSpeech)
        #expect(run.summary.committedFrameCount == speechFrames.count)
        #expect(try #require(run.commitStartInputFrameIndex) >= 8)
        #expect(try #require(run.commitStartInputFrameIndex) <= 10)
    }

    @Test func promptOnlyWarmupNeverCommitsSpeech() throws {
        let promptFrames = Self.makePromptFrames(count: 8)
        let silenceFrames = Self.makeSilenceFrames(count: 20)
        let frontend = try Self.makeFrontend(
            primaryDetections: Array(repeating: true, count: promptFrames.count) +
                Array(repeating: false, count: silenceFrames.count)
        )

        let run = try Self.runFrontend(
            frontend,
            preActivationFrames: promptFrames,
            postActivationFrames: silenceFrames
        )

        #expect(!run.summary.didCommitSpeech)
        #expect(run.summary.committedFrameCount == 0)
        #expect(run.endpointDetectionCount == 0)
    }

    @Test func activationKeepsImmediateSpeechOnsetFromBoundaryForward() throws {
        let preActivationFrames = Self.makePromptFrames(count: 5)
        let postActivationSpeechFrames = Self.makeSpeechFrames(count: 5, amplitude: 3_200)
        let frontend = try Self.makeFrontend(
            primaryDetections: Array(repeating: true, count: preActivationFrames.count + postActivationSpeechFrames.count)
        )

        let run = try Self.runFrontend(
            frontend,
            preActivationFrames: preActivationFrames,
            postActivationFrames: postActivationSpeechFrames
        )
        let flattenedSamples = run.committedFrames.flatMap { $0 }
        let firstAudibleSampleIndex = flattenedSamples.firstIndex {
            abs(Int($0)) > 150
        }

        #expect(run.summary.didCommitSpeech)
        #expect(try #require(firstAudibleSampleIndex) < 960)
    }

    @Test func sustainedTailSilenceAfterActivationTriggersExactlyOneEndpoint() throws {
        let warmupFrames = Self.makeStationaryNoiseFrames(count: 8)
        let speechFrames = Self.makeSpeechFrames(count: 20, amplitude: 3_000)
        let silenceFrames = Self.makeSilenceFrames(count: 35)
        let frontend = try Self.makeFrontend(
            primaryDetections: Array(repeating: false, count: warmupFrames.count) +
                Array(repeating: true, count: speechFrames.count) +
                Array(repeating: false, count: silenceFrames.count)
        )

        let run = try Self.runFrontend(
            frontend,
            preActivationFrames: warmupFrames,
            postActivationFrames: speechFrames + silenceFrames
        )

        #expect(run.summary.didCommitSpeech)
        #expect(run.endpointDetectionCount == 1)
        #expect(try #require(run.commitStartInputFrameIndex) <= 10)
    }

    @Test func continuousSpeechAfterActivationDoesNotAutoEndpoint() throws {
        let warmupFrames = Self.makeSilenceFrames(count: 6)
        let speechFrames = Self.makeSpeechFrames(count: 25, amplitude: 3_000)
        let frontend = try Self.makeFrontend(
            primaryDetections: Array(repeating: false, count: warmupFrames.count) +
                Array(repeating: true, count: speechFrames.count)
        )

        let run = try Self.runFrontend(
            frontend,
            preActivationFrames: warmupFrames,
            postActivationFrames: speechFrames
        )

        #expect(run.summary.didCommitSpeech)
        #expect(run.endpointDetectionCount == 0)
    }

    @Test func stationaryNoiseNeverCommitsSpeechEvenAfterActivation() throws {
        let frames = Self.makeStationaryNoiseFrames(count: 80)
        let frontend = try Self.makeFrontend(
            primaryDetections: Array(repeating: false, count: frames.count)
        )

        let run = try Self.runFrontend(
            frontend,
            preActivationFrames: Array(frames.prefix(10)),
            postActivationFrames: Array(frames.dropFirst(10))
        )

        #expect(!run.summary.didCommitSpeech)
        #expect(run.summary.committedFrameCount == 0)
    }

    @Test func quietSpeechIsBoostedBeforeCommit() throws {
        let warmupFrames = Self.makeSilenceFrames(count: 6)
        let quietSpeechFrames = Self.makeSpeechFrames(count: 8, amplitude: 260)
        let frontend = try Self.makeFrontend(
            primaryDetections: Array(repeating: false, count: warmupFrames.count) +
                Array(repeating: true, count: quietSpeechFrames.count)
        )

        let run = try Self.runFrontend(
            frontend,
            preActivationFrames: warmupFrames,
            postActivationFrames: quietSpeechFrames
        )

        let committedPeak = run.committedFrames
            .flatMap { $0 }
            .reduce(0.0) { partialResult, sample in
                max(partialResult, abs(Double(sample)) / Double(Int16.max))
            }
        let sourcePeak = quietSpeechFrames
            .flatMap { $0 }
            .reduce(0.0) { partialResult, sample in
                max(partialResult, abs(Double(sample)) / Double(Int16.max))
            }

        #expect(run.summary.didCommitSpeech)
        #expect(committedPeak > sourcePeak)
    }

    @Test func nonSpeechFramesAreSilencedDuringCommit() throws {
        let warmupFrames = Self.makeSilenceFrames(count: 6)
        let speechFrames = Self.makeSpeechFrames(count: 8, amplitude: 3_000)
        let noiseFrames = Self.makeStationaryNoiseFrames(count: 8)
        let frontend = try Self.makeFrontend(
            primaryDetections: Array(repeating: false, count: warmupFrames.count) +
                Array(repeating: true, count: speechFrames.count) +
                Array(repeating: false, count: noiseFrames.count)
        )

        let run = try Self.runFrontend(
            frontend,
            preActivationFrames: warmupFrames,
            postActivationFrames: speechFrames + noiseFrames
        )

        let sourceNoisePeak = noiseFrames
            .flatMap { $0 }
            .reduce(0.0) { partialResult, sample in
                max(partialResult, abs(Double(sample)) / Double(Int16.max))
            }
        let committedNoiseFrames = Array(run.committedFrames.suffix(noiseFrames.count))
        let committedNoisePeak = committedNoiseFrames
            .flatMap { $0 }
            .reduce(0.0) { partialResult, sample in
                max(partialResult, abs(Double(sample)) / Double(Int16.max))
            }

        #expect(run.summary.didCommitSpeech)
        #expect(committedNoisePeak < sourceNoisePeak)
    }
}

extension StreamingSpeechCaptureFrontendTests {
    private final class FrameSequenceSpeechDetector: @unchecked Sendable {
        private let lock = NSLock()
        private let detections: [Bool]
        private var index = 0

        init(detections: [Bool]) {
            self.detections = detections
        }

        func nextDecision() -> Bool {
            lock.lock()
            defer { lock.unlock() }

            guard !detections.isEmpty else { return false }
            let decision = detections[min(index, detections.count - 1)]
            index += 1
            return decision
        }
    }

    private static let frameSize = StreamingSpeechCaptureFrontend.Configuration.balanced.frameSize
    private static let sampleRate = StreamingSpeechCaptureFrontend.Configuration.balanced.sampleRate

    private static func makeFrontend(
        primaryDetections: [Bool],
        confirmationDetections: [Bool]? = nil
    ) throws -> StreamingSpeechCaptureFrontend {
        let primaryDetector = FrameSequenceSpeechDetector(detections: primaryDetections)
        let confirmationDetector = FrameSequenceSpeechDetector(
            detections: confirmationDetections ?? primaryDetections
        )

        return try StreamingSpeechCaptureFrontend(
            primarySpeechDetector: { _ in
                primaryDetector.nextDecision()
            },
            confirmationSpeechDetector: { _ in
                confirmationDetector.nextDecision()
            }
        )
    }

    private static func runFrontend(
        _ frontend: StreamingSpeechCaptureFrontend,
        preActivationFrames: [[Int16]],
        postActivationFrames: [[Int16]]
    ) throws -> (
        committedFrames: [[Int16]],
        endpointDetectionCount: Int,
        commitStartInputFrameIndex: Int?,
        summary: StreamingSpeechCaptureFrontend.Summary
    ) {
        var committedFrames: [[Int16]] = []
        var endpointDetectionCount = 0
        var commitStartInputFrameIndex: Int?

        for frame in preActivationFrames {
            let result = try frontend.process(frameSamples: frame)
            committedFrames.append(contentsOf: result.committedFrames)
            if result.didDetectEndpoint {
                endpointDetectionCount += 1
            }
        }

        frontend.activateRecordingWindow()

        for (frameOffset, frame) in postActivationFrames.enumerated() {
            let result = try frontend.process(frameSamples: frame)
            committedFrames.append(contentsOf: result.committedFrames)
            if commitStartInputFrameIndex == nil, !result.committedFrames.isEmpty {
                commitStartInputFrameIndex = preActivationFrames.count + frameOffset
            }
            if result.didDetectEndpoint {
                endpointDetectionCount += 1
            }
        }

        return (
            committedFrames: committedFrames,
            endpointDetectionCount: endpointDetectionCount,
            commitStartInputFrameIndex: commitStartInputFrameIndex,
            summary: frontend.summary()
        )
    }

    private static func makePromptFrames(count: Int) -> [[Int16]] {
        (0..<count).map { frameIndex in
            makeFrame { sampleIndex in
                let absoluteIndex = (frameIndex * frameSize) + sampleIndex
                let time = Double(absoluteIndex) / sampleRate
                let chirp = sin(2 * .pi * (1_250 + 280 * time) * time)
                return Int16(clamping: Int((4_500 * chirp).rounded()))
            }
        }
    }

    private static func makeSpeechFrames(count: Int, amplitude: Int16) -> [[Int16]] {
        (0..<count).map { frameIndex in
            makeFrame { sampleIndex in
                let absoluteIndex = (frameIndex * frameSize) + sampleIndex
                let time = Double(absoluteIndex) / sampleRate
                let envelope = 0.65 + 0.35 * sin(2 * .pi * 3.1 * time)
                let glide = 170 + 30 * sin(2 * .pi * 1.7 * time)
                let voiced =
                    sin(2 * .pi * glide * time) +
                    0.45 * sin(2 * .pi * glide * 2 * time) +
                    0.16 * sin(2 * .pi * 2_100 * time)
                let sample = Double(amplitude) * envelope * voiced
                return Int16(max(Double(Int16.min), min(sample, Double(Int16.max))))
            }
        }
    }

    private static func makeSilenceFrames(count: Int) -> [[Int16]] {
        Array(repeating: Array(repeating: 0, count: frameSize), count: count)
    }

    private static func makeStationaryNoiseFrames(count: Int) -> [[Int16]] {
        var state: UInt32 = 0x1234_ABCD

        return (0..<count).map { frameIndex in
            makeFrame { sampleIndex in
                let absoluteIndex = (frameIndex * frameSize) + sampleIndex
                let time = Double(absoluteIndex) / sampleRate
                state = 1_664_525 &* state &+ 1_013_904_223
                let whiteNoise = Double(Int32(bitPattern: state)) / Double(Int32.max)
                let hum =
                    sin(2 * .pi * 90 * time) +
                    0.55 * sin(2 * .pi * 180 * time) +
                    0.2 * sin(2 * .pi * 1_700 * time)
                let sample = 500 * hum + 180 * whiteNoise
                return Int16(max(Double(Int16.min), min(sample, Double(Int16.max))))
            }
        }
    }

    private static func makeFrame(_ sample: (Int) -> Int16) -> [Int16] {
        (0..<frameSize).map(sample)
    }
}
