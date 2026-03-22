@preconcurrency import AVFoundation
import FluidAudio
import Foundation

struct SpeechAwareGainProcessor: SpeechEnhancing {
    private enum Configuration {
        static let frameDuration: TimeInterval = 0.02
        static let hopDuration: TimeInterval = 0.01
        static let lowNoiseMarginDB: Double = 4
        static let fullNoiseMarginDB: Double = 8
        static let minimumConfidence: Double = 0
    }

    init() {}

    func enhanceAudioFile(
        at sourceURL: URL,
        analysis: AudioAnalysis
    ) throws -> SpeechEnhancementResult {
        guard sourceURL.pathExtension.lowercased() == "wav" else {
            return SpeechEnhancementResult(outputURL: sourceURL, didRewriteAudio: false)
        }

        guard analysis.speechEnhancementPlan.shouldEnhance else {
            return SpeechEnhancementResult(outputURL: sourceURL, didRewriteAudio: false)
        }

        let samples = try AudioConverter().resampleAudioFile(sourceURL)
        let enhancedSamples = Self.applyEnhancement(
            to: samples,
            sampleRate: Double(VadManager.sampleRate),
            analysis: analysis
        )

        guard enhancedSamples != samples else {
            return SpeechEnhancementResult(outputURL: sourceURL, didRewriteAudio: false)
        }

        let outputURL = try Self.writeSamples(enhancedSamples)
        return SpeechEnhancementResult(outputURL: outputURL, didRewriteAudio: true)
    }

    static func applyEnhancement(
        to samples: [Float],
        sampleRate: Double,
        analysis: AudioAnalysis
    ) -> [Float] {
        guard !samples.isEmpty,
              sampleRate > 0,
              analysis.speechEnhancementPlan.shouldEnhance else {
            return samples
        }

        let plan = analysis.speechEnhancementPlan
        let frameLength = max(1, Int(round(sampleRate * Configuration.frameDuration)))
        let hopLength = max(1, Int(round(sampleRate * Configuration.hopDuration)))
        let attackFrames = max(1, Int(round(plan.attackTime / Configuration.hopDuration)))
        let releaseFrames = max(1, Int(round(plan.releaseTime / Configuration.hopDuration)))
        let attackStep = 1.0 / Double(attackFrames)
        let releaseStep = 1.0 / Double(releaseFrames)
        let ceilingLinear = Self.dbToLinear(plan.limiterCeilingDBFS)

        var output = samples
        var smoothedGainDB = 0.0

        var frameStart = 0
        while frameStart < samples.count {
            let frameEnd = min(frameStart + frameLength, samples.count)
            let applyEnd = min(frameStart + hopLength, samples.count)
            let frame = Array(samples[frameStart..<frameEnd])
            let frameRMSDB = Self.rmsDBFS(from: frame)
            let confidence = Self.speechConfidence(
                frameRMSDB: frameRMSDB,
                noiseFloorDBFS: plan.estimatedNoiseFloorDBFS
            )
            let targetGainDB = plan.appliedGainDB * confidence
            let useAttack = abs(targetGainDB) > abs(smoothedGainDB)
            let step = useAttack ? attackStep : releaseStep
            smoothedGainDB += (targetGainDB - smoothedGainDB) * step
            let smoothedGainLinear = Self.dbToLinear(smoothedGainDB)

            for index in frameStart..<applyEnd {
                let scaled = Double(samples[index]) * smoothedGainLinear
                output[index] = Self.clampSample(scaled, ceilingLinear: ceilingLinear)
            }

            frameStart += hopLength
        }

        return output
    }

    static func speechConfidence(
        frameRMSDB: Double,
        noiseFloorDBFS: Double
    ) -> Double {
        guard frameRMSDB.isFinite, noiseFloorDBFS.isFinite else {
            return Configuration.minimumConfidence
        }

        let marginDB = frameRMSDB - noiseFloorDBFS
        if marginDB <= Configuration.lowNoiseMarginDB {
            return 0
        }
        if marginDB >= Configuration.fullNoiseMarginDB {
            return 1
        }

        let span = Configuration.fullNoiseMarginDB - Configuration.lowNoiseMarginDB
        return max(0, min(1, (marginDB - Configuration.lowNoiseMarginDB) / span))
    }

    static func rmsDBFS(from samples: [Float]) -> Double {
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

    static func dbToLinear(_ gainDB: Double) -> Double {
        guard gainDB.isFinite else { return 1 }
        return pow(10, gainDB / 20)
    }

//    Unused helper retained here in case the gain processor needs reverse conversion again.
//    static func linearToDB(_ gainLinear: Double) -> Double {
//        guard gainLinear > 0, gainLinear.isFinite else { return -160 }
//        return 20 * log10(gainLinear)
//    }

    static func clampSample(_ value: Double, ceilingLinear: Double) -> Float {
        guard value.isFinite else { return 0 }

        let clipped = min(max(value, -ceilingLinear), ceilingLinear)
        return Float(clipped)
    }

    private static func writeSamples(_ samples: [Float]) throws -> URL {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: TranscriptionUploadAudioFormat.macSampleRate,
            channels: TranscriptionUploadAudioFormat.macChannelCount,
            interleaved: false
        ) else {
            throw SpeechEnhancementError.unableToCreateOutputFormat
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("speech-enhanced-\(UUID().uuidString)")
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

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw SpeechEnhancementError.unableToCreateOutputBuffer
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channelData = buffer.int16ChannelData else {
            throw SpeechEnhancementError.unableToAccessOutputChannelData
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

enum SpeechEnhancementError: Error {
    case unableToCreateOutputFormat
    case unableToCreateOutputBuffer
    case unableToAccessOutputChannelData
}
