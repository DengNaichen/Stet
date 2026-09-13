import Foundation

/// On-device engines the user can select. Retired raw values such as
/// `localWhisper` and `sherpaOnnxSenseVoice` are not cases; loaders persist
/// `.default` instead.
public enum StoredTranscriptionEngine: String, CaseIterable, Sendable {
    case funASRNano
    case fluidAudio
    case appleSpeech

    public var displayName: String {
        switch self {
        case .funASRNano: return "Fun-ASR Nano"
        case .fluidAudio: return "Parakeet V3"
        case .appleSpeech: return "Apple Speech"
        }
    }

    public static let `default`: StoredTranscriptionEngine = .funASRNano
}
