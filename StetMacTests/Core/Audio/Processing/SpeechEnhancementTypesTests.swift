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
}
