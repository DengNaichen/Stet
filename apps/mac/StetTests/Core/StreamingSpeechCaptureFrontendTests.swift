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

    @Test func transientNoiseDoesNotTriggerCommit() throws {
        let warmupFrames = Self.makeSilenceFrames(count: 6)
        let transientFrames = Self.makeTransientNoiseFrames(count: 6)
        let frontend = try Self.makeFrontend(
            primaryDetections: Array(repeating: false, count: warmupFrames.count) +
                Array(repeating: true, count: transientFrames.count)
        )

        let run = try Self.runFrontend(
            frontend,
            preActivationFrames: warmupFrames,
            postActivationFrames: transientFrames
        )

        #expect(!run.summary.didCommitSpeech)
        #expect(run.summary.committedFrameCount == 0)
    }

    @Test func realVADDoesNotCommitKeyboardClicksOverRoomNoise() throws {
        let warmupFrames = Self.makeStationaryNoiseFrames(count: 10)
        let noisyKeyboardFrames = Self.makeKeyboardAndRoomNoiseFrames(count: 40)
        let frontend = try StreamingSpeechCaptureFrontend()

        let run = try Self.runFrontend(
            frontend,
            preActivationFrames: warmupFrames,
            postActivationFrames: noisyKeyboardFrames
        )
        #expect(!run.summary.didCommitSpeech)
        #expect(run.summary.committedFrameCount == 0)
        #expect(run.endpointDetectionCount == 0)
    }

    @Test func detectorInputIsNotAffectedByStreamingGain() throws {
        let warmupFrames = Self.makeSilenceFrames(count: 6)
        let marginalFrames = Self.makeGainSensitiveFrames(count: 6, amplitude: 220)
        let detectorThreshold = 0.018

        let frontend = try StreamingSpeechCaptureFrontend(
            primarySpeechDetector: { frame in
                Self.peakAmplitude(of: frame) >= detectorThreshold
            },
            confirmationSpeechDetector: { frame in
                Self.peakAmplitude(of: frame) >= detectorThreshold
            }
        )

        let run = try Self.runFrontend(
            frontend,
            preActivationFrames: warmupFrames,
            postActivationFrames: marginalFrames
        )

        #expect(!run.summary.didCommitSpeech)
        #expect(run.summary.committedFrameCount == 0)
    }

    @Test func activationNoiseCalibrationBlocksStableSpeechLikeRoomTone() throws {
        let warmupFrames = Self.makePromptFrames(count: 8)
        let roomToneFrames = Self.makeRoomDroneFrames(count: 40, amplitude: 80)
        let detectionCount = warmupFrames.count + roomToneFrames.count
        let frontend = try Self.makeFrontend(
            primaryDetections: Array(repeating: true, count: detectionCount),
            confirmationDetections: Array(repeating: true, count: detectionCount)
        )

        let run = try Self.runFrontend(
            frontend,
            preActivationFrames: warmupFrames,
            postActivationFrames: roomToneFrames
        )

        #expect(!run.summary.didCommitSpeech)
        #expect(run.summary.committedFrameCount == 0)
        #expect(run.endpointDetectionCount == 0)
    }

    @Test func realVADDoesNotCommitLowZeroCrossingRoomToneAfterSilenceWarmup() throws {
        let promptFrames = Self.makePromptFrames(count: 8)
        let silenceFrames = Self.makeSilenceFrames(count: 10)
        let roomToneFrames = Self.makeLowZeroCrossingRoomToneFrames(
            count: 40,
            amplitude: 80,
            noiseAmplitude: 0
        )
        let frontend = try StreamingSpeechCaptureFrontend()

        let run = try Self.runFrontend(
            frontend,
            preActivationFrames: promptFrames,
            postActivationFrames: silenceFrames + roomToneFrames
        )
        let diagnostics = frontend.diagnostics()

        #expect(!run.summary.didCommitSpeech)
        #expect(run.summary.committedFrameCount == 0)
        #expect(
            diagnostics.noiseFloorDBFS >=
                StreamingSpeechCaptureFrontend.Configuration.balanced.minimumLearnableNoiseFloorDBFS
        )
    }

    @Test func lowZeroCrossingGateRejectsLoudTonalNoiseEvenWhenDetectorsVoteSpeech() throws {
        let warmupFrames = Self.makeSilenceFrames(count: 6)
        let loudRoomToneFrames = Self.makeLowZeroCrossingRoomToneFrames(
            count: 24,
            amplitude: 200,
            noiseAmplitude: 0
        )
        let frontend = try Self.makeFrontend(
            primaryDetections: Array(repeating: false, count: warmupFrames.count) +
                Array(repeating: true, count: loudRoomToneFrames.count),
            confirmationDetections: Array(repeating: false, count: warmupFrames.count) +
                Array(repeating: true, count: loudRoomToneFrames.count)
        )

        let run = try Self.runFrontend(
            frontend,
            preActivationFrames: warmupFrames,
            postActivationFrames: loudRoomToneFrames
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

    private static func makeTransientNoiseFrames(count: Int) -> [[Int16]] {
        (0..<count).map { frameIndex in
            makeFrame { sampleIndex in
                guard sampleIndex == frameSize / 2 else { return 0 }
                return frameIndex.isMultiple(of: 2) ? 30_000 : -30_000
            }
        }
    }

    private static func makeKeyboardAndRoomNoiseFrames(count: Int) -> [[Int16]] {
        let clickFrameOffsets = [2, 5, 9, 13, 16, 20, 24, 27, 31, 35]
        let clickWidth = 120
        var state: UInt32 = 0xBEEF_FEED

        return (0..<count).map { frameIndex in
            makeFrame { sampleIndex in
                let absoluteIndex = (frameIndex * frameSize) + sampleIndex
                let time = Double(absoluteIndex) / sampleRate
                state = 1_664_525 &* state &+ 1_013_904_223
                let whiteNoise = Double(Int32(bitPattern: state)) / Double(Int32.max)
                let hum =
                    sin(2 * .pi * 90 * time) +
                    0.55 * sin(2 * .pi * 180 * time) +
                    0.24 * sin(2 * .pi * 1_650 * time)
                var sample = (720 * hum) + (220 * whiteNoise)

                for clickFrameOffset in clickFrameOffsets {
                    let clickCenter = (clickFrameOffset * frameSize) + (frameSize / 2)
                    let distance = abs(absoluteIndex - clickCenter)
                    guard distance <= clickWidth else { continue }

                    let normalizedDistance = Double(distance) / Double(clickWidth)
                    let envelope = pow(max(0, 1 - normalizedDistance), 2.1)
                    let click =
                        sin(2 * .pi * 2_900 * time) +
                        0.72 * sin(2 * .pi * 4_700 * time) +
                        0.32 * sin(2 * .pi * 6_000 * time)
                    sample += 1_350 * envelope * click
                }

                return Int16(max(Double(Int16.min), min(sample, Double(Int16.max))))
            }
        }
    }

    private static func makeRoomDroneFrames(count: Int, amplitude: Int16) -> [[Int16]] {
        var state: UInt32 = 0xDEAD_BEEF

        return (0..<count).map { frameIndex in
            makeFrame { sampleIndex in
                let absoluteIndex = (frameIndex * frameSize) + sampleIndex
                let time = Double(absoluteIndex) / sampleRate
                state = 1_103_515_245 &* state &+ 12_345
                let whiteNoise = Double(Int32(bitPattern: state)) / Double(Int32.max)
                let envelope = 0.82 + (0.18 * sin(2 * .pi * 2.2 * time))
                let drone =
                    sin(2 * .pi * 110 * time) +
                    (0.62 * sin(2 * .pi * 220 * time)) +
                    (0.28 * sin(2 * .pi * 330 * time)) +
                    (0.08 * sin(2 * .pi * 1_800 * time))
                let sample = (Double(amplitude) * envelope * drone) + (24 * whiteNoise)
                return Int16(max(Double(Int16.min), min(sample, Double(Int16.max))))
            }
        }
    }

    private static func makeLowZeroCrossingRoomToneFrames(
        count: Int,
        amplitude: Int16,
        noiseAmplitude: Double
    ) -> [[Int16]] {
        var state: UInt32 = 0xCAFE_BABE

        return (0..<count).map { frameIndex in
            makeFrame { sampleIndex in
                let absoluteIndex = (frameIndex * frameSize) + sampleIndex
                let time = Double(absoluteIndex) / sampleRate
                state = 1_664_525 &* state &+ 1_013_904_223
                let whiteNoise = Double(Int32(bitPattern: state)) / Double(Int32.max)
                let roomTone =
                    sin(2 * .pi * 120 * time) +
                    (0.72 * sin(2 * .pi * 240 * time)) +
                    (0.33 * sin(2 * .pi * 360 * time)) +
                    (0.04 * sin(2 * .pi * 1_500 * time))
                let sample = (Double(amplitude) * roomTone) + (noiseAmplitude * whiteNoise)
                return Int16(max(Double(Int16.min), min(sample, Double(Int16.max))))
            }
        }
    }

    private static func makeGainSensitiveFrames(count: Int, amplitude: Int16) -> [[Int16]] {
        (0..<count).map { frameIndex in
            makeFrame { sampleIndex in
                let absoluteIndex = (frameIndex * frameSize) + sampleIndex
                let time = Double(absoluteIndex) / sampleRate
                let carrier = sin(2 * .pi * 210 * time) + (0.24 * sin(2 * .pi * 420 * time))
                let sample = Double(amplitude) * carrier
                return Int16(max(Double(Int16.min), min(sample, Double(Int16.max))))
            }
        }
    }

    private static func peakAmplitude(of frame: ArraySlice<Int16>) -> Double {
        frame.reduce(0.0) { partialResult, sample in
            max(partialResult, abs(Double(sample)) / Double(Int16.max))
        }
    }

    private static func makeFrame(_ sample: (Int) -> Int16) -> [Int16] {
        (0..<frameSize).map(sample)
    }
}
