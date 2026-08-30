import Foundation
import StetCore

enum TranscriptionLanguageRouting {
    static func resolveEngine(primary: String, secondary: String?) -> TranscriptionEngine {
        _ = primary
        _ = secondary
        return .funASRNano
    }
}
