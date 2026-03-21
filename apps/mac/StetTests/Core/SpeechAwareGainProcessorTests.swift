import AVFoundation
import Foundation
import Testing

@testable import Stet

@Suite("Speech-Aware Gain Processor", .serialized)
struct SpeechAwareGainProcessorTests {
    @Test func silenceDoesNotRequestOrApplyEnhancement() {
        let samples = Self.makeSilenceSamples(count: 16_000)
        let analysis = Self.makeAnalysis(
            discard: true,
            speechLevelDBFS: -160,
            noiseFloorDBFS: -160,
            overallPeakDBFS: -160,
            speechPeakDBFS: -160,
            recommendedGainDB: 0
        )

        #expect(!analysis.speechEnhancementPlan.shouldEnhance)
        #expect(analysis.speechEnhancementPlan.targetSpeechLevelDBFS == -20)
        #expect(analysis.speechEnhancementPlan.maxBoostDB == 10)
        #expect(analysis.speechEnhancementPlan.maxCutDB == -4)
        #expect(analysis.speechEnhancementPlan.limiterCeilingDBFS == -1)
        #expect(abs(analysis.speechEnhancementPlan.attackTime - 0.12) < 0.000_1)
        #expect(abs(analysis.speechEnhancementPlan.releaseTime - 0.4) < 0.000_1)

        let output = SpeechAwareGainProcessor.applyEnhancement(
            to: samples,
            sampleRate: 16_000,
            analysis: analysis
        )

        #expect(output == samples)
    }

    @Test func stationaryNoiseDoesNotGetBoostedWhenEnhancementIsDisabled() {
        let samples = Self.makeStationaryNoiseSamples(count: 16_000)
        let analysis = Self.makeAnalysis(
            discard: true,
            speechLevelDBFS: -44,
            noiseFloorDBFS: -46,
            overallPeakDBFS: -34,
            speechPeakDBFS: -38,
            recommendedGainDB: 0
        )

        let output = SpeechAwareGainProcessor.applyEnhancement(
            to: samples,
            sampleRate: 16_000,
            analysis: analysis
        )

        #expect(output == samples)
    }

    @Test func quietSpeechIsBoostedButStaysBounded() {
        let fixture = Self.makeSpeechFixture(amplitude: 0.07)
        let analysis = Self.makeAnalysis(
            discard: false,
            speechLevelDBFS: -33.5,
            noiseFloorDBFS: -46.0,
            overallPeakDBFS: -29.5,
            speechPeakDBFS: -27.0,
            recommendedGainDB: 10
        )

        let output = SpeechAwareGainProcessor.applyEnhancement(
            to: fixture.samples,
            sampleRate: 16_000,
            analysis: analysis
        )

        let inputSpeechRMS = SpeechAwareGainProcessor.rmsDBFS(
            from: Array(fixture.samples[fixture.speechRange])
        )
        let outputSpeechRMS = SpeechAwareGainProcessor.rmsDBFS(
            from: Array(output[fixture.speechRange])
        )
        let ceilingLinear = SpeechAwareGainProcessor.dbToLinear(-1)

        #expect(outputSpeechRMS > inputSpeechRMS)
        #expect(Self.maxAbs(output) <= ceilingLinear + 0.000_1)
    }

    @Test func loudSpeechIsNotPushedHigher() {
        let fixture = Self.makeSpeechFixture(amplitude: 0.45)
        let analysis = Self.makeAnalysis(
            discard: false,
            speechLevelDBFS: -12.0,
            noiseFloorDBFS: -46.0,
            overallPeakDBFS: -7.0,
            speechPeakDBFS: -5.5,
            recommendedGainDB: -4
        )

        let output = SpeechAwareGainProcessor.applyEnhancement(
            to: fixture.samples,
            sampleRate: 16_000,
            analysis: analysis
        )

        let inputSpeechRMS = SpeechAwareGainProcessor.rmsDBFS(
            from: Array(fixture.samples[fixture.speechRange])
        )
        let outputSpeechRMS = SpeechAwareGainProcessor.rmsDBFS(
            from: Array(output[fixture.speechRange])
        )

        #expect(outputSpeechRMS <= inputSpeechRMS)
        #expect(Self.maxAbs(output) <= Self.maxAbs(fixture.samples) + 0.000_1)
    }

    @Test func limiterPreventsClippingOnHotSpeech() {
        let fixture = Self.makeSpeechFixture(amplitude: 0.12, includePeakSpike: true)
        let analysis = Self.makeAnalysis(
            discard: false,
            speechLevelDBFS: -29.0,
            noiseFloorDBFS: -48.0,
            overallPeakDBFS: -0.3,
            speechPeakDBFS: -0.3,
            recommendedGainDB: 10
        )

        let output = SpeechAwareGainProcessor.applyEnhancement(
            to: fixture.samples,
            sampleRate: 16_000,
            analysis: analysis
        )

        let ceilingLinear = SpeechAwareGainProcessor.dbToLinear(-1)
        #expect(Self.maxAbs(output) <= ceilingLinear + 0.000_1)
    }

    @Test func enhancementIsDeterministicForSameInput() {
        let fixture = Self.makeSpeechFixture(amplitude: 0.08)
        let analysis = Self.makeAnalysis(
            discard: false,
            speechLevelDBFS: -31.5,
            noiseFloorDBFS: -46.5,
            overallPeakDBFS: -26.0,
            speechPeakDBFS: -24.0,
            recommendedGainDB: 10
        )

        let first = SpeechAwareGainProcessor.applyEnhancement(
            to: fixture.samples,
            sampleRate: 16_000,
            analysis: analysis
        )
        let second = SpeechAwareGainProcessor.applyEnhancement(
            to: fixture.samples,
            sampleRate: 16_000,
            analysis: analysis
        )

        #expect(first == second)
    }
}

extension SpeechAwareGainProcessorTests {
    private struct SpeechFixture {
        let samples: [Float]
        let speechRange: Range<Int>
    }

    private static func makeAnalysis(
        discard: Bool,
        speechLevelDBFS: Double,
        noiseFloorDBFS: Double,
        overallPeakDBFS: Double,
        speechPeakDBFS: Double,
        recommendedGainDB: Double
    ) -> AudioAnalysis {
        AudioAnalysis(
            shouldDiscardAsNoSpeech: discard,
            speechFrameRatio: discard ? 0 : 0.72,
            confirmationSpeechFrameRatio: discard ? 0 : 0.72,
            longestSpeechDurationSeconds: discard ? 0 : 0.9,
            totalSpeechDurationSeconds: discard ? 0 : 1.0,
            rawSpeechFrameRatio: discard ? 0 : 0.78,
            noiseFloorDBFS: noiseFloorDBFS,
            speechLevelP75DBFS: speechLevelDBFS,
            speechPeakDBFS: speechPeakDBFS,
            overallPeakDBFS: overallPeakDBFS,
            speechSignalToNoiseMarginDB: max(0, speechLevelDBFS - noiseFloorDBFS),
            recommendedGainDB: recommendedGainDB
        )
    }

    private static func makeSilenceSamples(count: Int) -> [Float] {
        Array(repeating: 0, count: count)
    }

    private static func makeStationaryNoiseSamples(count: Int) -> [Float] {
        var state: UInt32 = 0x1234_ABCD
        return (0..<count).map { index in
            state = 1_664_525 &* state &+ 1_013_904_223
            let white = Double(Int32(bitPattern: state)) / Double(Int32.max)
            let t = Double(index) / 16_000.0
            let hum = 0.3 * sin(2 * .pi * 90.0 * t) + 0.12 * sin(2 * .pi * 180.0 * t)
            return Float(0.015 * white + 0.02 * hum)
        }
    }

    private static func makeSpeechFixture(
        amplitude: Float,
        includePeakSpike: Bool = false
    ) -> SpeechFixture {
        let sampleCount = 16_000
        let speechRange = 2_400..<13_600
        var samples = Array(repeating: Float(0), count: sampleCount)

        for index in speechRange {
            let t = Double(index) / 16_000.0
            let envelope = 0.55 + 0.45 * sin(2 * .pi * 2.5 * t)
            let carrier = 0.72 * sin(2 * .pi * 175.0 * t)
                + 0.22 * sin(2 * .pi * 350.0 * t)
                + 0.08 * sin(2 * .pi * 525.0 * t)
            samples[index] = amplitude * Float(envelope) * Float(carrier)
        }

        if includePeakSpike {
            samples[8_000] = 0.998
        }

        return SpeechFixture(samples: samples, speechRange: speechRange)
    }

    private static func maxAbs(_ samples: [Float]) -> Double {
        samples.reduce(0) { max($0, Double(abs($1))) }
    }
}
