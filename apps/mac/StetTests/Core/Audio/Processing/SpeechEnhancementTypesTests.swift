import Foundation
import Testing

@testable import Stet

@Suite("Speech Enhancement Plan")
struct SpeechEnhancementPlanTests {
    @Test func disabledPlanHasCorrectDefaults() {
        let plan = SpeechEnhancementPlan.disabled
        
        #expect(!plan.shouldEnhance)
        #expect(plan.targetSpeechLevelDBFS == -20)
        #expect(plan.estimatedSpeechLevelDBFS == -160)
        #expect(plan.estimatedNoiseFloorDBFS == -160)
        #expect(plan.appliedGainDB == 0)
        #expect(plan.maxBoostDB == 10)
        #expect(plan.maxCutDB == -4)
        #expect(plan.limiterCeilingDBFS == -1)
        #expect(abs(plan.attackTime - 0.12) < 0.0001)
        #expect(abs(plan.releaseTime - 0.4) < 0.0001)
    }
    
    @Test func customPlanRetainsAllProperties() {
        let plan = SpeechEnhancementPlan(
            shouldEnhance: true,
            targetSpeechLevelDBFS: -18,
            estimatedSpeechLevelDBFS: -25,
            estimatedNoiseFloorDBFS: -45,
            appliedGainDB: 7,
            maxBoostDB: 12,
            maxCutDB: -6,
            limiterCeilingDBFS: -0.5,
            attackTime: 0.1,
            releaseTime: 0.3
        )
        
        #expect(plan.shouldEnhance)
        #expect(plan.targetSpeechLevelDBFS == -18)
        #expect(plan.estimatedSpeechLevelDBFS == -25)
        #expect(plan.estimatedNoiseFloorDBFS == -45)
        #expect(plan.appliedGainDB == 7)
        #expect(plan.maxBoostDB == 12)
        #expect(plan.maxCutDB == -6)
        #expect(plan.limiterCeilingDBFS == -0.5)
        #expect(abs(plan.attackTime - 0.1) < 0.0001)
        #expect(abs(plan.releaseTime - 0.3) < 0.0001)
    }
}

@Suite("Speech Enhancement Result")
struct SpeechEnhancementResultTests {
    @Test func resultRetainsOutputURLAndRewriteFlag() {
        let url = URL(fileURLWithPath: "/tmp/enhanced.wav")
        let result = SpeechEnhancementResult(outputURL: url, didRewriteAudio: true)
        
        #expect(result.outputURL == url)
        #expect(result.didRewriteAudio)
    }
    
    @Test func resultCanIndicateNoRewrite() {
        let url = URL(fileURLWithPath: "/tmp/original.wav")
        let result = SpeechEnhancementResult(outputURL: url, didRewriteAudio: false)
        
        #expect(result.outputURL == url)
        #expect(!result.didRewriteAudio)
    }
}
