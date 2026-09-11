import Foundation

/// On-device engines the user can select. Retired raw values such as
/// `localWhisper` and `sherpaOnnxSenseVoice` are not cases; loaders persist
/// `.default` instead.
public enum StoredTranscriptionEngine: String, CaseIterable, Sendable {
    case funASRNano
    case fluidAudio

    public var displayName: String {
        switch self {
        case .funASRNano: return "Fun-ASR Nano"
        case .fluidAudio: return "Parakeet V3"
        }
    }

    public static let `default`: StoredTranscriptionEngine = .funASRNano
}
