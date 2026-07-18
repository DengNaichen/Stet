import Foundation

protocol DictationSessionPersisting: AnyObject {
    func heartbeat()
    func getSession() -> DictationSession?
    func saveSession(_ session: DictationSession)

    @discardableResult
    func updateState(
        for sessionId: String,
        to state: DictationState,
        error: String?
    ) -> Bool

    @discardableResult
    func updateText(
        for sessionId: String,
        partial: String,
        final: String
    ) -> Bool
}

protocol DictationVolumeTransporting: AnyObject {
    func updateVolume(_ level: Float)
    func readVolume() -> Float
}

extension SharedDictationManager: DictationSessionPersisting, DictationVolumeTransporting {}
