import FluidAudio
import Foundation

struct AudioAnalysis: Sendable {
    let shouldDiscardAsNoSpeech: Bool
    let speechFrameRatio: Double
    let confirmationSpeechFrameRatio: Double
    let longestSpeechDurationSeconds: Double
    let totalSpeechDurationSeconds: Double
    let rawSpeechFrameRatio: Double
    let noiseFloorDBFS: Double
    let speechLevelP75DBFS: Double

    var summaryLine: String {
        """
        wouldDiscard=\(shouldDiscardAsNoSpeech) \
        rawSpeechFrameRatio=\(String(format: "%.3f", rawSpeechFrameRatio)) \
        speechFrameRatio=\(String(format: "%.3f", speechFrameRatio)) \
        confirmationSpeechFrameRatio=\(String(format: "%.3f", confirmationSpeechFrameRatio)) \
        totalSpeechSeconds=\(String(format: "%.3f", totalSpeechDurationSeconds)) \
        longestSpeechSeconds=\(String(format: "%.3f", longestSpeechDurationSeconds)) \
        noiseFloorDBFS=\(String(format: "%.1f", noiseFloorDBFS)) \
        speechLevelP75DBFS=\(String(format: "%.1f", speechLevelP75DBFS))
        """
    }
}

enum AudioSignalAnalyzer {
    struct Configuration {
        static let speechProbabilityThreshold: Float = 0.8
        static let minimumSpeechSegmentDuration: TimeInterval = 0.4
    }

    static func analyze(
        samples: [Float],
        sampleRate: Double
    ) async throws -> AudioAnalysis {
        guard !samples.isEmpty, sampleRate > 0 else {
            return AudioAnalysis(
                shouldDiscardAsNoSpeech: true,
                speechFrameRatio: 0,
                confirmationSpeechFrameRatio: 0,
                longestSpeechDurationSeconds: 0,
                totalSpeechDurationSeconds: 0,
                rawSpeechFrameRatio: 0,
                noiseFloorDBFS: -160,
                speechLevelP75DBFS: -160
            )
        }

        // Initialize FluidAudio VadManager
        let manager = try await VadManager(
            config: VadConfig(defaultThreshold: Configuration.speechProbabilityThreshold)
        )
        
        // Use default segmentation config from the library
        let allSegments = try await manager.segmentSpeech(samples, config: .default)
        
        // Filter out very short segments that are likely transient noises (coughs, sneezes, clicks).
        // Actual speech segments generally last longer than 400ms.
        let segments = allSegments.filter { ($0.endTime - $0.startTime) >= Configuration.minimumSpeechSegmentDuration }
        
        let shouldDiscardAsNoSpeech = segments.isEmpty
        
        // Calculate basic stats based on the filtered segments.
        let totalSpeechDurationSeconds = segments.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
        let longestSpeechDurationSeconds = segments.map { $0.endTime - $0.startTime }.max() ?? 0.0
        let totalDuration = Double(samples.count) / sampleRate
        let speechFrameRatio = totalDuration > 0 ? totalSpeechDurationSeconds / totalDuration : 0.0

        return AudioAnalysis(
            shouldDiscardAsNoSpeech: shouldDiscardAsNoSpeech,
            speechFrameRatio: speechFrameRatio,
            confirmationSpeechFrameRatio: speechFrameRatio, // Simplified
            longestSpeechDurationSeconds: longestSpeechDurationSeconds,
            totalSpeechDurationSeconds: totalSpeechDurationSeconds,
            rawSpeechFrameRatio: speechFrameRatio,
            noiseFloorDBFS: 0, // No longer calculating manual noise floor
            speechLevelP75DBFS: 0 // No longer calculating manual speech level
        )
    }
}
