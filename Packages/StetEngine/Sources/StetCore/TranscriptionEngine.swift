import Foundation

public enum TranscriptionEngine: Equatable, Sendable {
    case fluidAudio
    case funASRNano

    public var displayName: String {
        switch self {
        case .fluidAudio: "Parakeet V3"
        case .funASRNano: "Fun-ASR Nano"
        }
    }
}
