import Foundation

public enum TranscriptionEngine: Equatable, Sendable {
    case fluidAudio
    case funASRNano
    case localWhisper(languageHint: String?)

    public var displayName: String {
        switch self {
        case .fluidAudio: "Parakeet V3"
        case .funASRNano: "Fun-ASR Nano"
        case .localWhisper: "Whisper"
        }
    }
}
