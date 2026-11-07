#if os(macOS)
    import Foundation
    import StetVisuals

    protocol AudioFeatureSource: Sendable {
        func makeAudioFeatureStream() async -> AsyncStream<MacDictationCapsuleVisualSignals>
    }

    typealias AudioFeatureBridge = LatestValueBroadcast<MacDictationCapsuleVisualSignals>
#endif
