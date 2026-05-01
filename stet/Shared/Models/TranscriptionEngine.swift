import Foundation

public enum TranscriptionEngine: Equatable, Sendable {
    case fluidAudio
    case localWhisper(languageHint: String?)
    case sherpaOnnxSenseVoice
}
