import Foundation

struct SpeechEnhancementPlan: Sendable {
    let shouldEnhance: Bool
    let targetSpeechLevelDBFS: Double
    let estimatedSpeechLevelDBFS: Double
    let estimatedNoiseFloorDBFS: Double
    let appliedGainDB: Double
    let maxBoostDB: Double
    let maxCutDB: Double
    let limiterCeilingDBFS: Double
    let attackTime: TimeInterval
    let releaseTime: TimeInterval

    static let disabled = Self(
        shouldEnhance: false,
        targetSpeechLevelDBFS: -20,
        estimatedSpeechLevelDBFS: -160,
        estimatedNoiseFloorDBFS: -160,
        appliedGainDB: 0,
        maxBoostDB: 10,
        maxCutDB: -4,
        limiterCeilingDBFS: -1,
        attackTime: 0.12,
        releaseTime: 0.4
    )
}

struct SpeechEnhancementResult: Sendable {
    let outputURL: URL
    let didRewriteAudio: Bool
}

protocol SpeechEnhancing: Sendable {
    func enhanceAudioFile(
        at sourceURL: URL,
        analysis: AudioAnalysis
    ) throws -> SpeechEnhancementResult
}
