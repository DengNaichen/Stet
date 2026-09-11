#if os(macOS)
    import Foundation
    import Testing

    @testable import StetVisuals

    @Suite("Watercolor Orb Motion")
    struct MacWatercolorOrbMotionTests {
        @Test func voiceScalesTheWholeOrbWithTheLegacyCurveButKeepsButtonsStable() {
            var motion = MacWatercolorOrbMotion()
            motion.setState(.starting)
            advance(&motion, seconds: 3, level: 0)
            #expect(abs(motion.frame.orbScale - 0.98) < 0.001)

            motion.setState(.listening)
            advance(&motion, seconds: 1, level: 0.08)
            #expect(abs(motion.frame.orbScale - (0.98 + pow(0.08, 0.4) * 0.1)) < 0.001)
            advance(&motion, seconds: 1, level: 1)
            #expect(abs(motion.frame.orbDiameter - 69.12) < 0.001)
            #expect(motion.frame.buttonDiameter == 28)
            #expect(motion.frame.scale == 1)
            #expect(motion.frame.orbDiameter < 106)

            let loud = motion.frame.orbScale
            motion.advance(by: 0.025, level: 0)
            #expect(motion.frame.orbScale < loud && motion.frame.orbScale > 1.06)
            advance(&motion, seconds: 3, level: 0)
            #expect(abs(motion.frame.orbScale - 0.98) < 0.001)
        }

        @Test func voiceScaleStaysBoundedAndStopsForReducedMotion() {
            var motion = MacWatercolorOrbMotion()
            motion.setState(.listening)
            for level in [2.0, -1.0, .nan, .infinity, 0.5] {
                advance(&motion, seconds: 1, level: level)
                #expect(motion.frame.orbScale.isFinite)
                #expect((0.98...1.08).contains(motion.frame.orbScale))
            }
            motion.setState(.listening, reduceMotion: true)
            #expect(motion.frame.orbScale == 1)
            advance(&motion, seconds: 1, level: 1)
            #expect(motion.frame.orbScale == 1)
            motion.setState(.processing, reduceMotion: true)
            #expect(motion.frame.orbDiameter == 44)
        }

        @Test func microphoneMappingMatchesBrowserWithoutChangingManualLevel() {
            let background = MacDictationCapsuleVisualSignals(
                bands: [], estimatedSummary: .init(level: 0.45, flowX: 0, flowY: 0, groupedBands: .zero),
                inputRMS: 0.003
            )
            #expect(background.estimatedSummary.level == 0.45)
            #expect(MacWatercolorOrbMotion.voiceLevel(for: background) == 0)
            let speech = MacDictationCapsuleVisualSignals(bands: [], inputRMS: 0.0472)
            #expect(abs(MacWatercolorOrbMotion.voiceLevel(for: speech) - 0.6) < 0.000_001)
            let manual = MacDictationCapsuleVisualSignals(body: 0.6, presence: 0, pulse: 0, articulation: 0)
            #expect(abs(MacWatercolorOrbMotion.voiceLevel(for: manual) - 0.6) < 0.000_001)
        }

        @Test func quietMicrophoneCanEnterIdleWavesEvenWithNonzeroLegacyLevel() {
            var motion = MacWatercolorOrbMotion()
            motion.setState(.listening)
            let signals = MacDictationCapsuleVisualSignals(
                bands: [], estimatedSummary: .init(level: 0.45, flowX: 0, flowY: 0, groupedBands: .zero),
                inputRMS: 0.003
            )
            advance(&motion, seconds: 3, level: MacWatercolorOrbMotion.voiceLevel(for: signals))
            #expect(motion.frame.idleWave.x > 0)
            #expect(motion.frame.diameter == 64)
        }

        @Test func silenceAddsWavesWithoutEnteringThinking() {
            var motion = MacWatercolorOrbMotion()
            motion.setState(.listening)
            advance(&motion, seconds: 4, level: 0)

            #expect(motion.state == .listening)
            #expect(motion.frame.diameter == 64)
            #expect(motion.frame.motion == 1)
            #expect(motion.frame.idleWave.x > 0)
            #expect(motion.frame.idleWave.z > 0)
        }

        @Test func speechRetainsOriginalResponseAndFadesOutIdleWaves() {
            var motion = MacWatercolorOrbMotion()
            motion.setState(.listening)
            advance(&motion, seconds: 3, level: 0)
            let quietVelocity = motion.velocity
            advance(&motion, seconds: 1, level: 0.6)

            #expect(motion.frame.idleWave.x == 0)
            #expect(motion.frame.idleWave.y == 0)
            #expect(motion.frame.motion == 1)
            #expect(abs(motion.energy - 0.6) < 0.001)
            #expect(motion.velocity > quietVelocity * 3)
            #expect(motion.frame.tone > 0.5)
        }

        @Test func thinkingIgnoresMicrophoneAndKeepsMovingAtReducedAmplitude() {
            var quiet = MacWatercolorOrbMotion()
            quiet.setState(.listening)
            advance(&quiet, seconds: 1, level: 0.6)
            var loud = quiet
            quiet.setState(.processing)
            loud.setState(.processing)
            let entry = quiet.frame.phase
            for _ in 0..<160 {
                quiet.advance(by: 0.025, level: 0)
                loud.advance(by: 0.025, level: 1)
                #expect(quiet.frame == loud.frame)
            }

            #expect(quiet.frame.phase > entry)
            #expect(quiet.frame.anchor == entry)
            #expect(abs(quiet.frame.diameter - 44) < 0.001)
            #expect(abs(quiet.frame.orbDiameter - 44) < 0.001)
            #expect(abs(quiet.frame.motion - 0.4) < 0.001)
            #expect(quiet.frame.idleWave.x == 0)
        }

        @Test func sineHasApprovedRangeAndPeriod() {
            let samples = (0...104).map { MacWatercolorOrbMotion.thinkingLevel(at: Double($0) * 0.025) }
            #expect(abs((samples.min() ?? 0) - 0.04) < 0.000_001)
            #expect(abs((samples.max() ?? 0) - 0.16) < 0.000_001)
            #expect(abs(samples[0] - samples[104]) < 0.000_001)
        }

        @Test func enteringAndInterruptingThinkingPreservesPaintPhase() {
            var motion = MacWatercolorOrbMotion()
            motion.setState(.listening)
            advance(&motion, seconds: 1, level: 0.6)
            let entry = motion.frame
            motion.setState(.processing)
            #expect(motion.frame.phase == entry.phase)
            #expect(motion.frame.diameter == entry.diameter)
            #expect(motion.frame.orbDiameter == entry.orbDiameter)
            motion.advance(by: 0.025, level: 0)
            #expect(motion.frame.diameter > 44 && motion.frame.diameter < 64)

            motion.setState(.listening)
            motion.advance(by: 0.025, level: 0.6)
            let interrupted = motion.frame
            motion.setState(.processing)
            #expect(motion.frame == interrupted)

            motion.setState(.listening)
            advance(&motion, seconds: 2, level: 0.6)
            #expect(abs(motion.frame.diameter - 64) < 0.001)
            #expect(abs(motion.frame.motion - 1) < 0.001)
        }

        @Test func hiddenAndReducedMotionStopTimeButStillReflectState() {
            var motion = MacWatercolorOrbMotion()
            motion.setState(.processing, reduceMotion: true)
            let reduced = motion.frame
            advance(&motion, seconds: 3, level: 1)
            #expect(motion.frame == reduced)
            #expect(motion.frame.diameter == 44)
            motion.setState(.listening, reduceMotion: true)
            #expect(motion.frame.diameter == 64)
            motion.setState(.hidden)
            let hidden = motion.frame
            advance(&motion, seconds: 3, level: 1)
            #expect(motion.frame == hidden)
        }

        @Test func suspendedClockAndInvalidInputCannotCauseAJumpOrNaN() {
            var motion = MacWatercolorOrbMotion()
            motion.setState(.listening)
            let before = motion.frame.phase
            motion.advance(by: 900, level: .nan)
            #expect(motion.frame.phase - before < 0.1)
            #expect(motion.frame.phase.isFinite && motion.frame.tone.isFinite)
            let valid = motion.frame
            motion.advance(by: .infinity, level: .infinity)
            motion.advance(by: -1, level: 1)
            #expect(motion.frame == valid)
        }

        private func advance(_ motion: inout MacWatercolorOrbMotion, seconds: Double, level: Double) {
            for _ in 0..<Int(seconds * 40) {
                motion.advance(by: 0.025, level: level, random: { 0.5 })
            }
        }
    }

    @Suite("Watercolor Orb Presentation")
    struct MacWatercolorOrbPresentationTests {
        @Test func buttonsFollowMirroredDownwardCurvesAndFitExistingPanel() {
            let end = MacWatercolorOrbLayout.buttonPosition(progress: 1, side: 1)
            let middle = MacWatercolorOrbLayout.buttonPosition(progress: 0.5, side: 1)
            #expect(middle.y > end.y)
            #expect(end.x * 2 > MacWatercolorOrbLayout.hitDiameter)
            #expect(hypot(end.x, end.y) > 32 + MacWatercolorOrbLayout.buttonDiameter / 2)
            for step in 0...100 {
                let t = Double(step) / 100
                let right = MacWatercolorOrbLayout.buttonPosition(progress: t, side: 1)
                let left = MacWatercolorOrbLayout.buttonPosition(progress: t, side: -1)
                #expect(right.x == -left.x && right.y == left.y)
                #expect(abs(right.x) + 22 < 370 / 2)
                #expect(abs(right.y) + 22 < 106 / 2)
            }
        }

        @Test func reversingRevealStartsFromCurrentPositionAndTerminates() {
            var animation = MacWatercolorOrbPresentation()
            let start = Date(timeIntervalSinceReferenceDate: 100)
            animation.setVisible(true, at: start, reduceMotion: false)
            let reversal = start.addingTimeInterval(0.2)
            let before = animation.progress(at: reversal)
            animation.setVisible(false, at: reversal, reduceMotion: false)
            #expect(animation.progress(at: reversal) == before)
            #expect(animation.progress(at: reversal.addingTimeInterval(0.1)) < before)
            #expect(animation.progress(at: reversal.addingTimeInterval(1)) == 0)
            #expect(!animation.isAnimating(at: reversal.addingTimeInterval(1)))
        }

        @Test func reducedMotionImmediatelyExposesFinalHitTargets() {
            var animation = MacWatercolorOrbPresentation()
            let now = Date()
            animation.setVisible(true, at: now, reduceMotion: true)
            #expect(animation.progress(at: now) == 1)
            #expect(!animation.isAnimating(at: now))
        }
    }
#endif
