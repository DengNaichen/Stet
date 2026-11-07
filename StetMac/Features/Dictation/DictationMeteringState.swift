import Foundation
import Combine
#if os(macOS)
    import StetCore
    import StetVisuals
#endif

/// High-frequency visualization changes are observed only by the capsule.
@MainActor
final class DictationMeteringState: ObservableObject {
    @Published var recordingLevel = 0.0
    #if os(macOS)
        @Published var audioFeatures = MacDictationCapsuleVisualSignals.zero
    #endif
}
