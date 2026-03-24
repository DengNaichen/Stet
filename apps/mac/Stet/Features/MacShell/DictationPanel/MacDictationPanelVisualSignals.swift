#if os(macOS)
    import Foundation

    struct MacDictationPanelVisualSignals: Equatable {
        let body: Double
        let presence: Double
        let pulse: Double
        let articulation: Double

        init(
            body: Double,
            presence: Double,
            pulse: Double,
            articulation: Double
        ) {
            self.body = Self.clamp(body)
            self.presence = Self.clamp(presence)
            self.pulse = Self.clamp(pulse)
            self.articulation = Self.clamp(articulation)
        }

        static let zero = MacDictationPanelVisualSignals(
            body: 0,
            presence: 0,
            pulse: 0,
            articulation: 0
        )

        private static func clamp(_ value: Double) -> Double {
            min(max(value, 0), 1)
        }
    }
#endif
