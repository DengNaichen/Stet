import Foundation

protocol DictationSessionPersisting: AnyObject {
    func heartbeat()
    func getSession() -> DictationSession?

    @discardableResult
    func claimSessionForStart(sessionId: String) -> Bool

    @discardableResult
    func updateState(
        for sessionId: String,
        to state: DictationState,
        error: String?
    ) -> Bool

    @discardableResult
    func transitionState(
        for sessionId: String,
        from expectedStates: [DictationState],
        to state: DictationState,
        error: String?
    ) -> Bool

    @discardableResult
    func updateText(
        for sessionId: String,
        partial: String,
        final: String
    ) -> Bool

    @discardableResult
    func completeSession(
        for sessionId: String,
        from expectedStates: [DictationState],
        finalText: String
    ) -> Bool
}

protocol DictationVolumeTransporting: AnyObject {
    func updateVolume(_ level: Float)
    func readVolume() -> Float
}

extension SharedDictationManager: DictationSessionPersisting, DictationVolumeTransporting {}
