#if os(macOS)
    import Foundation

    enum MacWatercolorOrbLayout {
        static let buttonDiameter = 28.0
        static let hitDiameter = 44.0
        static let glassSpacing = 11.56007428520794
        static let revealDuration = 0.55

        // The selected native-lab pose becomes the fully interactive product endpoint.
        private static let selectedProgress = 0.8643167688116247
        private static let reach = 60.15538985143712
        private static let drop = 12.6339011004039
        private static let bend = 11.88852372917651

        static func buttonPosition(progress: Double, side: Double) -> CGPoint {
            let t = min(1, max(0, progress)) * selectedProgress
            let u = 1 - t
            let x = 3 * u * u * t * reach * 0.22 + 3 * u * t * t * reach * 0.74 + t * t * t * reach
            let y = 3 * u * t * (bend + drop) + t * t * t * drop
            return CGPoint(x: side * x, y: y)
        }
    }

    /// Samples the whole curve, including reversals during an unfinished reveal.
    struct MacWatercolorOrbPresentation {
        private var from = 0.0
        private var target = 0.0
        private var startedAt = Date.distantPast

        func progress(at date: Date) -> Double {
            let t = min(1, max(0, date.timeIntervalSince(startedAt) / MacWatercolorOrbLayout.revealDuration))
            return from + (target - from) * t * t * (3 - 2 * t)
        }

        mutating func setVisible(_ visible: Bool, at date: Date, reduceMotion: Bool) {
            let destination = visible ? 1.0 : 0.0
            guard destination != target || reduceMotion else { return }
            from = reduceMotion ? destination : progress(at: date)
            target = destination
            startedAt = date
        }

        func isAnimating(at date: Date) -> Bool {
            from != target && date.timeIntervalSince(startedAt) < MacWatercolorOrbLayout.revealDuration
        }
    }
#endif
