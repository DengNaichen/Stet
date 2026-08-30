import Foundation

public enum StoredTranscriptionEngine: String, CaseIterable, Sendable {
    case fluidAudio
    case funASRNano
    case localWhisper

    public var displayName: String {
        switch self {
        case .fluidAudio: return "Parakeet V3"
        case .funASRNano: return "Fun-ASR Nano"
        case .localWhisper: return "Whisper"
        }
    }

    public static let `default`: StoredTranscriptionEngine = .funASRNano
}
