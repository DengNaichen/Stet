#if os(macOS)
    import Foundation

    /// The approved browser preset. The preview's 0.60 level is an input, not a persisted gain.
    enum MacWatercolorOrbPreset {
        static let speed = 1.25
        static let grain = 0.14
        static let weave = 0.77
        static let diameter = 64.0
        static let thinkingDiameter = 44.0
        static let thinkingPeriod = 2.6
        static let thinkingMotion = 0.40
        static let frameInterval = 1.0 / 40.0
    }

    struct MacWatercolorOrbFrame: Equatable {
        var phase = 3.0
        var anchor = 3.0
        var tone = 0.0
        var thinkingBlend = 0.0
        var idleWave = SIMD3<Double>.zero

        var diameter: Double {
            MacWatercolorOrbPreset.diameter
                + (MacWatercolorOrbPreset.thinkingDiameter - MacWatercolorOrbPreset.diameter) * thinkingBlend
        }

        var motion: Double {
            1 + (MacWatercolorOrbPreset.thinkingMotion - 1) * thinkingBlend
        }
    }

    /// Owns time and envelopes independently of SwiftUI updates and microphone delivery cadence.
    /// Only a session state change selects Thinking; silence never does.
    struct MacWatercolorOrbMotion {
        private(set) var frame = MacWatercolorOrbFrame()
        private(set) var state = MacDictationCapsuleVisualState.hidden
        private(set) var energy = 0.0
        private(set) var velocity = MacWatercolorOrbPreset.speed
        private var speechLevel = 0.0
        private var cycle = 0.0
        private var reduceMotion = false
        private var idle = IdleWaves()

        var isVisible: Bool {
            switch state {
            case .starting, .listening, .processing: true
            case .hidden, .result, .error: false
            }
        }

        mutating func setState(_ state: MacDictationCapsuleVisualState, reduceMotion: Bool = false) {
            if state == .processing && self.state != .processing {
                // Re-entering during the blend keeps its anchor, avoiding a paint-position jump.
                if frame.thinkingBlend < 0.01 { frame.anchor = frame.phase }
                cycle = 0
            }
            self.state = state
            self.reduceMotion = reduceMotion
            if reduceMotion {
                frame.thinkingBlend = state == .processing ? 1 : 0
                frame.idleWave = .zero
            }
        }

        mutating func advance(
            by elapsed: Double,
            level: Double,
            random: () -> Double = { Double.random(in: 0...1) }
        ) {
            guard isVisible, !reduceMotion, elapsed.isFinite, elapsed > 0 else { return }
            // A suspended/occluded window must not fast-forward through a large paint displacement.
            let dt = min(elapsed, 0.05)
            let thinking = state == .processing
            if !thinking { speechLevel = level.isFinite ? min(1, max(0, level)) : 0 }
            frame.thinkingBlend = follow(frame.thinkingBlend, thinking ? 1 : 0, dt, 0.115)
            cycle = (cycle + dt).truncatingRemainder(dividingBy: MacWatercolorOrbPreset.thinkingPeriod)
            let sine = Self.thinkingLevel(at: cycle)
            let input = speechLevel * (1 - frame.thinkingBlend) + sine * frame.thinkingBlend
            energy = follow(energy, input, dt, input > energy ? 0.055 : 0.32)
            frame.tone = follow(frame.tone, energy, dt, energy > frame.tone ? 0.12 : 0.58)
            let targetVelocity = MacWatercolorOrbPreset.speed * (1 + energy * 4)
            velocity = follow(velocity, targetVelocity, dt, 0.24)
            frame.phase += dt * velocity
            frame.idleWave = idle.advance(
                by: dt, level: speechLevel, energy: energy, enabled: !thinking, random: random
            )
        }

        static func thinkingLevel(at time: Double) -> Double {
            0.10 + 0.06 * sin(2 * .pi * time / MacWatercolorOrbPreset.thinkingPeriod)
        }

        static func voiceLevel(for signals: MacDictationCapsuleVisualSignals) -> Double {
            guard let rms = signals.inputRMS else { return signals.body }
            // Same microphone mapping as the browser. Preserve the legacy themes' dB curve.
            return sqrt(min(1, max(0, (Double(rms) - 0.004) / 0.12)))
        }

        private func follow(_ value: Double, _ target: Double, _ dt: Double, _ tau: Double) -> Double {
            value + (target - value) * (1 - exp(-dt / tau))
        }
    }

    private struct IdleWaves {
        var silence = 0.0
        var blend = 0.0
        var phase = 0.0
        var height = 0.035
        var smallHeight = 0.012
        var rate = 1.2
        var targetHeight = 0.035
        var targetSmallHeight = 0.012
        var targetRate = 1.2
        var nextChange = 0.0

        mutating func advance(
            by dt: Double, level: Double, energy: Double, enabled: Bool, random: () -> Double
        ) -> SIMD3<Double> {
            silence = level > 0.035 || !enabled ? 0 : silence + dt
            let active = enabled && silence > 0.65 && energy < 0.06
            blend = active ? min(1, blend + dt / 0.6) : max(0, blend - dt / 0.12)
            if active {
                nextChange -= dt
                if nextChange <= 0 {
                    targetHeight = 0.025 + random() * 0.025
                    targetSmallHeight = 0.006 + random() * 0.010
                    targetRate = 0.95 + random() * 0.40
                    nextChange = 2.8 + random() * 1.8
                }
                let follow = 1 - exp(-dt / 0.85)
                height += (targetHeight - height) * follow
                smallHeight += (targetSmallHeight - smallHeight) * follow
                rate += (targetRate - rate) * follow
            }
            if blend > 0 { phase += dt * rate }
            return SIMD3(height * blend, smallHeight * blend, phase)
        }
    }
#endif
