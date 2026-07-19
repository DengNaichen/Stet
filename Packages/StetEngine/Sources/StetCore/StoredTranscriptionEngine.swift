import Foundation

public enum StoredTranscriptionEngine: String, CaseIterable, Sendable {
    case fluidAudio
    case funASRNano
    case localWhisper
    case sherpaOnnxSenseVoice

    public var displayName: String {
        switch self {
        case .fluidAudio: return "Parakeet V3"
        case .funASRNano: return "Fun-ASR Nano"
        case .localWhisper: return "Whisper"
        case .sherpaOnnxSenseVoice: return "SenseVoice"
        }
    }

    public static let `default`: StoredTranscriptionEngine = .sherpaOnnxSenseVoice
}
