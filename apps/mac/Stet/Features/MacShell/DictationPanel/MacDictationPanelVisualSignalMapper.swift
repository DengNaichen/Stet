#if os(macOS)
import Foundation

enum MacDictationPanelVisualSignalMapper {
    struct State {
        var body: Double
        var fast: Double
        var presence: Double
        var pulse: Double
        var articulation: Double

        var visualSignals: MacDictationPanelVisualSignals {
            MacDictationPanelVisualSignals(
                body: body,
                presence: presence,
                pulse: pulse,
                articulation: articulation
            )
        }
    }

    private enum Timing {
        static let bodyAttack: TimeInterval = 0.12
        static let bodyRelease: TimeInterval = 0.34
        static let fastAttack: TimeInterval = 0.026
        static let fastRelease: TimeInterval = 0.11
        static let presenceAttack: TimeInterval = 0.05
        static let presenceRelease: TimeInterval = 0.20
        static let pulseAttack: TimeInterval = 0.012
        static let pulseRelease: TimeInterval = 0.09
        static let articulationAttack: TimeInterval = 0.02
        static let articulationRelease: TimeInterval = 0.12
        static let minimumTimeConstant: TimeInterval = 0.001
    }

    static func initialState(level: Double, isVoiceReactive: Bool) -> State {
        let clampedLevel = amplifiedLevel(level)
        let basePresence = isVoiceReactive ? presenceTarget(body: clampedLevel, fast: clampedLevel) : 0

        return State(
            body: clampedLevel,
            fast: clampedLevel,
            presence: basePresence,
            pulse: 0,
            articulation: min(1, clampedLevel * 0.22)
        )
    }

    static func step(
        state: State,
        targetLevel: Double,
        deltaTime: TimeInterval,
        isVoiceReactive: Bool
    ) -> State {
        let target = isVoiceReactive ? amplifiedLevel(targetLevel) : 0

        let nextFast = smooth(
            current: state.fast,
            target: target,
            deltaTime: deltaTime,
            attack: Timing.fastAttack,
            release: Timing.fastRelease
        )

        let nextBody = smooth(
            current: state.body,
            target: target,
            deltaTime: deltaTime,
            attack: Timing.bodyAttack,
            release: Timing.bodyRelease
        )

        let transient = max(0, nextFast - nextBody)
        let pulseTarget = isVoiceReactive ? clamp01(transient * 4.20 + target * 0.10) : 0
        let nextPulse = smooth(
            current: state.pulse,
            target: pulseTarget,
            deltaTime: deltaTime,
            attack: Timing.pulseAttack,
            release: Timing.pulseRelease
        )

        let nextPresence = smooth(
            current: state.presence,
            target: isVoiceReactive ? presenceTarget(body: nextBody, fast: nextFast) : 0,
            deltaTime: deltaTime,
            attack: Timing.presenceAttack,
            release: Timing.presenceRelease
        )

        let articulationTarget = isVoiceReactive ? clamp01(
            transient * 2.0
                + max(0, nextFast - nextPresence * 0.66) * 1.02
                + target * 0.22
        ) : 0
        let nextArticulation = smooth(
            current: state.articulation,
            target: articulationTarget,
            deltaTime: deltaTime,
            attack: Timing.articulationAttack,
            release: Timing.articulationRelease
        )

        return State(
            body: nextBody,
            fast: nextFast,
            presence: nextPresence,
            pulse: nextPulse,
            articulation: nextArticulation
        )
    }

    private static func presenceTarget(body: Double, fast: Double) -> Double {
        clamp01(max(body * 1.16 + fast * 0.58, fast * 1.02))
    }

    private static func smooth(
        current: Double,
        target: Double,
        deltaTime: TimeInterval,
        attack: TimeInterval,
        release: TimeInterval
    ) -> Double {
        let timeConstant = target > current ? attack : release
        let alpha = 1.0 - exp(-deltaTime / max(timeConstant, Timing.minimumTimeConstant))
        return current + (target - current) * alpha
    }

    private static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func amplifiedLevel(_ value: Double) -> Double {
        clamp01(value * 1.68)
    }
}
#endif
