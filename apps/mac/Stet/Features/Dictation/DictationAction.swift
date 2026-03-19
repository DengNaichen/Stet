import Foundation

enum DictationAction: Equatable {
    case startTapped
    case stopTapped
    case resetTapped
    case transcriptionSucceeded(String)
    case clipboardPending(String)
    case transcriptionFailed(DictationFailure)
}
