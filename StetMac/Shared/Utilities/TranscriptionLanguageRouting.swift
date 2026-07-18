import Foundation
import StetCore

enum TranscriptionLanguageRouting {
    static func resolveEngine(primary _: String, secondary _: String?) -> TranscriptionEngine {
        .sherpaOnnxSenseVoice
    }
}
