#if os(macOS)
    import Foundation
    import simd

    public struct MacDictationAudioBandFeature: Equatable, Sendable {
        public var x: Float
        public var y: Float
        public var weight: Float

        public init(x: Float, y: Float, weight: Float) {
            self.x = x
            self.y = y
            self.weight = max(0, weight)
        }

        static let zero = MacDictationAudioBandFeature(x: 0, y: 0, weight: 0)
    }

    public struct MacDictationAudioVisualSummary: Equatable, Sendable {
        public var level: Float
        public var flowX: Float
        public var flowY: Float
        public var groupedBands: SIMD4<Float>

        public init(
            level: Float,
            flowX: Float,
            flowY: Float,
            groupedBands: SIMD4<Float>
        ) {
            self.level = max(0, min(level, 1))
            self.flowX = flowX
            self.flowY = flowY
            self.groupedBands = simd_clamp(groupedBands, .zero, SIMD4<Float>(repeating: 1))
        }

        public static let zero = MacDictationAudioVisualSummary(
            level: 0,
            flowX: 0,
            flowY: 0,
            groupedBands: .zero
        )
    }

    public struct MacDictationCapsuleVisualSignals: Equatable, Sendable {
        public static let bandCount = 12

        public let bands: [MacDictationAudioBandFeature]
        public let estimatedSummary: MacDictationAudioVisualSummary

        public init(
            bands: [MacDictationAudioBandFeature],
            estimatedSummary: MacDictationAudioVisualSummary = .zero
        ) {
            let normalizedBands = Array(
                (bands + Array(repeating: .zero, count: Self.bandCount)).prefix(Self.bandCount)
            )
            self.bands = normalizedBands
            self.estimatedSummary = estimatedSummary
        }

        public init(
            body: Double,
            presence: Double,
            pulse: Double,
            articulation: Double
        ) {
            let groupedBands = SIMD4<Float>(
                Float(max(0, min(body, 1))),
                Float(max(0, min(presence, 1))),
                Float(max(0, min(pulse, 1))),
                Float(max(0, min(articulation, 1)))
            )

            var bands: [MacDictationAudioBandFeature] = []
            for index in 0..<Self.bandCount {
                let bucket = min(3, index / 3)
                bands.append(
                    MacDictationAudioBandFeature(
                        x: Float(index + 1) / Float(Self.bandCount + 1),
                        y: 0.25 + 0.12 * Float(bucket),
                        weight: groupedBands[bucket] / 3
                    )
                )
            }

            self.init(
                bands: bands,
                estimatedSummary: MacDictationAudioVisualSummary(
                    level: groupedBands.max(),
                    flowX: (groupedBands[2] - groupedBands[0]) * 0.18,
                    flowY: (groupedBands[3] - groupedBands[1]) * 0.18,
                    groupedBands: groupedBands
                )
            )
        }

        public static let zero = MacDictationCapsuleVisualSignals(bands: [])

        public var body: Double { Double(estimatedSummary.level) }
        public var presence: Double { Double(estimatedSummary.groupedBands[1]) }
        public var pulse: Double { Double(estimatedSummary.groupedBands[2]) }
        public var articulation: Double { Double(estimatedSummary.groupedBands[3]) }

        public func scaled(by gain: Float) -> MacDictationCapsuleVisualSignals {
            MacDictationCapsuleVisualSignals(
                bands: bands.map {
                    MacDictationAudioBandFeature(x: $0.x, y: $0.y, weight: $0.weight * gain)
                },
                estimatedSummary: MacDictationAudioVisualSummary(
                    level: estimatedSummary.level * gain,
                    flowX: estimatedSummary.flowX * gain,
                    flowY: estimatedSummary.flowY * gain,
                    groupedBands: estimatedSummary.groupedBands * gain
                )
            )
        }
    }

    public enum MacDictationAudioFieldConstants {
        public static let fieldGridSize = 48
        public static let fieldSigmaX: Float = 0.09
        public static let fieldSigmaY: Float = 0.11
        public static let fieldBlurSigma: Float = 0.9
        public static let gradientBlurSigma: Float = 0.8
        public static let minFrequency: Float = 80
        public static let maxFrequency: Float = 9_000
        public static let fftSize = 2_048
    }
#endif
