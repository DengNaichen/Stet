import FluidAudio
import Foundation

struct AudioAnalysis: Sendable {
    let shouldDiscardAsNoSpeech: Bool
    let speechFrameRatio: Double
    let noiseFloorDBFS: Double
    let speechLevelP75DBFS: Double
    let overallPeakDBFS: Double
    let recommendedGainDB: Double

    var speechEnhancementPlan: SpeechEnhancementPlan {
        AudioSignalAnalyzer.makeSpeechEnhancementPlan(from: self)
    }

    var summaryLine: String {
        """
        wouldDiscard=\(shouldDiscardAsNoSpeech) \
        speechFrameRatio=\(String(format: "%.3f", speechFrameRatio)) \
        noiseFloorDBFS=\(String(format: "%.1f", noiseFloorDBFS)) \
        speechLevelP75DBFS=\(String(format: "%.1f", speechLevelP75DBFS)) \
        overallPeakDBFS=\(String(format: "%.1f", overallPeakDBFS)) \
        recommendedGainDB=\(String(format: "%.1f", recommendedGainDB)) \
        shouldEnhance=\(speechEnhancementPlan.shouldEnhance)
        """
    }
}

enum AudioSignalAnalyzer {
    struct Configuration {
        static let speechProbabilityThreshold: Float = 0.8
        static let minimumSpeechSegmentDuration: TimeInterval = 0.4
        static let analysisFrameDuration: TimeInterval = 0.02
        static let analysisHopDuration: TimeInterval = 0.01
        static let targetSpeechLevelDBFS: Double = -20
        static let maxBoostDB: Double = 10
        static let maxCutDB: Double = -4
        static let limiterCeilingDBFS: Double = -1
        static let lowNoiseMarginDB: Double = 4
        static let fullNoiseMarginDB: Double = 8
        static let enhancementGainEpsilonDB: Double = 0.5
        static let attenuationThresholdAboveTargetDB: Double = 6
    }

    static func analyze(
        samples: [Float],
        sampleRate: Double
    ) async throws -> AudioAnalysis {
        guard !samples.isEmpty, sampleRate > 0 else {
            return AudioAnalysis(
                shouldDiscardAsNoSpeech: true,
                speechFrameRatio: 0,
                noiseFloorDBFS: -160,
                speechLevelP75DBFS: -160,
                overallPeakDBFS: -160,
                recommendedGainDB: 0
            )
        }

        let analysisSampleRate = Double(VadManager.sampleRate)
        let analysisSamples = try normalizeSamplesForAnalysis(samples: samples, sampleRate: sampleRate)

        let manager = try await VadManager(
            config: VadConfig(defaultThreshold: Configuration.speechProbabilityThreshold)
        )
        let allSegments = try await manager.segmentSpeech(analysisSamples, config: .default)
        let segments = allSegments.filter { ($0.endTime - $0.startTime) >= Configuration.minimumSpeechSegmentDuration }

        let shouldDiscardAsNoSpeech = segments.isEmpty
        let totalDuration = Double(analysisSamples.count) / analysisSampleRate
        let speechFrameRatio =
            totalDuration > 0
            ? segments.reduce(0.0) { $0 + ($1.endTime - $1.startTime) } / totalDuration
            : 0.0

        let overallPeakDBFS = peakDBFS(from: analysisSamples)
        let speechMask = makeSpeechMask(
            sampleCount: analysisSamples.count,
            sampleRate: analysisSampleRate,
            segments: segments
        )
        let frameMetrics = frameMetrics(
            samples: analysisSamples,
            sampleRate: analysisSampleRate,
            speechMask: speechMask
        )
        let speechLevelP75DBFS = percentile(frameMetrics.speechFrameLevels, 0.75) ?? -160
        let noiseFloorDBFS =
            percentile(frameMetrics.noiseFrameLevels, 0.2)
            ?? max(-160, speechLevelP75DBFS - 12)
        let recommendedGainDB = recommendedGainDB(
            speechLevelDBFS: speechLevelP75DBFS,
            noiseFloorDBFS: noiseFloorDBFS,
            overallPeakDBFS: overallPeakDBFS
        )

        return AudioAnalysis(
            shouldDiscardAsNoSpeech: shouldDiscardAsNoSpeech,
            speechFrameRatio: speechFrameRatio,
            noiseFloorDBFS: noiseFloorDBFS,
            speechLevelP75DBFS: speechLevelP75DBFS,
            overallPeakDBFS: overallPeakDBFS,
            recommendedGainDB: recommendedGainDB
        )
    }

    static func makeSpeechEnhancementPlan(from analysis: AudioAnalysis) -> SpeechEnhancementPlan {
        guard !analysis.shouldDiscardAsNoSpeech else {
            return .disabled
        }

        let appliedGainDB = analysis.recommendedGainDB
        let shouldEnhance = abs(appliedGainDB) >= Configuration.enhancementGainEpsilonDB

        return SpeechEnhancementPlan(
            shouldEnhance: shouldEnhance,
            targetSpeechLevelDBFS: Configuration.targetSpeechLevelDBFS,
            estimatedSpeechLevelDBFS: analysis.speechLevelP75DBFS,
            estimatedNoiseFloorDBFS: analysis.noiseFloorDBFS,
            appliedGainDB: appliedGainDB,
            maxBoostDB: Configuration.maxBoostDB,
            maxCutDB: Configuration.maxCutDB,
            limiterCeilingDBFS: Configuration.limiterCeilingDBFS,
            attackTime: 0.12,
            releaseTime: 0.4
        )
    }

    private static func normalizeSamplesForAnalysis(
        samples: [Float],
        sampleRate: Double
    ) throws -> [Float] {
        let targetSampleRate = Double(VadManager.sampleRate)
        guard abs(sampleRate - targetSampleRate) > 0.000_1 else {
            return samples
        }

        return try AudioConverter().resample(samples, from: sampleRate)
    }

    private static func frameMetrics(
        samples: [Float],
        sampleRate: Double,
        speechMask: [Bool]
    ) -> (speechFrameLevels: [Double], noiseFrameLevels: [Double]) {
        let frameLength = max(1, Int(round(sampleRate * Configuration.analysisFrameDuration)))
        let hopLength = max(1, Int(round(sampleRate * Configuration.analysisHopDuration)))
        guard !samples.isEmpty else {
            return ([], [])
        }

        var speechFrameLevels: [Double] = []
        var noiseFrameLevels: [Double] = []

        var start = 0
        while start < samples.count {
            let end = min(start + frameLength, samples.count)
            let frame = Array(samples[start..<end])
            let levelDBFS = rmsDBFS(from: frame)
            let speechCoverage = coverage(in: speechMask, start: start, end: end)
            if speechCoverage >= 0.5 {
                speechFrameLevels.append(levelDBFS)
            } else {
                noiseFrameLevels.append(levelDBFS)
            }
            start += hopLength
        }

        return (speechFrameLevels, noiseFrameLevels)
    }

    private static func makeSpeechMask(
        sampleCount: Int,
        sampleRate: Double,
        segments: [VadSegment]
    ) -> [Bool] {
        guard sampleCount > 0, sampleRate > 0 else {
            return []
        }

        var mask = Array(repeating: false, count: sampleCount)
        let roundedRate = Int(sampleRate.rounded())

        for segment in segments {
            let lower = max(0, min(segment.startSample(sampleRate: roundedRate), sampleCount))
            let upper = max(lower, min(segment.endSample(sampleRate: roundedRate), sampleCount))
            guard upper > lower else { continue }
            for index in lower..<upper {
                mask[index] = true
            }
        }

        return mask
    }

    private static func coverage(in mask: [Bool], start: Int, end: Int) -> Double {
        guard start < end, start >= 0, end <= mask.count else { return 0 }

        var activeCount = 0
        for index in start..<end where mask[index] {
            activeCount += 1
        }

        return Double(activeCount) / Double(end - start)
    }

    private static func peakDBFS(from samples: [Float]) -> Double {
        guard let peak = samples.map({ abs($0) }).max(), peak > 0 else {
            return -160
        }

        return 20 * log10(Double(peak))
    }

    private static func rmsDBFS(from samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -160 }

        var sumSquares = 0.0
        for sample in samples {
            let value = Double(sample)
            sumSquares += value * value
        }

        let meanSquare = sumSquares / Double(samples.count)
        guard meanSquare > 0 else { return -160 }
        return 20 * log10(sqrt(meanSquare))
    }

    private static func percentile(_ values: [Double], _ percentile: Double) -> Double? {
        guard !values.isEmpty else { return nil }

        let sorted = values.sorted()
        let clampedPercentile = min(max(percentile, 0), 1)
        let position = clampedPercentile * Double(sorted.count - 1)
        let lowerIndex = Int(floor(position))
        let upperIndex = Int(ceil(position))
        if lowerIndex == upperIndex {
            return sorted[lowerIndex]
        }

        let lowerWeight = Double(upperIndex) - position
        let upperWeight = position - Double(lowerIndex)
        return sorted[lowerIndex] * lowerWeight + sorted[upperIndex] * upperWeight
    }

    private static func recommendedGainDB(
        speechLevelDBFS: Double,
        noiseFloorDBFS: Double,
        overallPeakDBFS: Double
    ) -> Double {
        guard speechLevelDBFS.isFinite, noiseFloorDBFS.isFinite, overallPeakDBFS.isFinite else {
            return 0
        }

        let rawGainDB = Configuration.targetSpeechLevelDBFS - speechLevelDBFS
        let boundedGainDB: Double
        if rawGainDB >= 0 {
            boundedGainDB = min(rawGainDB, Configuration.maxBoostDB)
        } else {
            let shouldAttenuate =
                overallPeakDBFS > Configuration.limiterCeilingDBFS
                || speechLevelDBFS
                    > (Configuration.targetSpeechLevelDBFS + Configuration.attenuationThresholdAboveTargetDB)
            boundedGainDB = shouldAttenuate ? max(rawGainDB, Configuration.maxCutDB) : 0
        }

        let noiseMarginDB = max(0, speechLevelDBFS - noiseFloorDBFS)
        let scaledGainDB: Double
        if boundedGainDB > 0 {
            let scale: Double
            if noiseMarginDB <= Configuration.lowNoiseMarginDB {
                scale = 0
            } else if noiseMarginDB >= Configuration.fullNoiseMarginDB {
                scale = 1
            } else {
                scale =
                    (noiseMarginDB - Configuration.lowNoiseMarginDB)
                    / (Configuration.fullNoiseMarginDB - Configuration.lowNoiseMarginDB)
            }
            scaledGainDB = boundedGainDB * scale
        } else {
            scaledGainDB = boundedGainDB
        }

        let peakSafeGainDB = min(scaledGainDB, Configuration.limiterCeilingDBFS - overallPeakDBFS)
        return peakSafeGainDB.isFinite ? peakSafeGainDB : 0
    }
}
