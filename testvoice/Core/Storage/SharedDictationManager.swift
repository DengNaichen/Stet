import Foundation

enum DictationState: String, Codable {
    case idle
    case launching
    case warming
    case recording
    case transcribing
    case ready
    case inserted
    case cancelled
    case failed
    case timeout
    
    // Commands from keyboard to background app
    case requestStart
    case requestStop
}

struct DictationSession: Codable {
    let sessionId: String
    let createdAt: Date
    var updatedAt: Date
    var state: DictationState
    var partialText: String = ""
    var finalText: String = ""
    var revision: Int = 0
    var error: String?
}

class SharedDictationManager {
    static let shared = SharedDictationManager()
    private let appGroupIdentifier = "group.NaichengDeng.testvoice"
    private let sessionKey = "dictation.session"
    private let heartbeatKey = "dictation.heartbeat"

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    func heartbeat() {
        defaults?.set(Date().timeIntervalSince1970, forKey: heartbeatKey)
    }

    func mainAppAlive(within seconds: TimeInterval) -> Bool {
        guard let ts = defaults?.object(forKey: heartbeatKey) as? TimeInterval, ts > 0 else { return false }
        return Date().timeIntervalSince1970 - ts < seconds
    }
    
    func saveSession(_ session: DictationSession) {
        if let data = try? JSONEncoder().encode(session) {
            defaults?.set(data, forKey: sessionKey)
            defaults?.synchronize()
        }
    }
    
    func getSession() -> DictationSession? {
        guard let data = defaults?.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(DictationSession.self, from: data)
    }
    
    func updateState(_ state: DictationState, error: String? = nil) {
        var session = getSession() ?? DictationSession(sessionId: UUID().uuidString, createdAt: Date(), updatedAt: Date(), state: .idle)
        session.state = state
        session.updatedAt = Date()
        session.error = error
        saveSession(session)
    }
    
    func updateError(_ error: String) {
        guard var session = getSession() else { return }
        session.error = error
        saveSession(session)
    }
    
    func updateText(partial: String, final: String) {
        guard var session = getSession() else { return }
        session.partialText = partial
        session.finalText = final
        session.revision += 1
        session.updatedAt = Date()
        saveSession(session)
    }
    
    func clearSession() {
        defaults?.removeObject(forKey: sessionKey)
        defaults?.synchronize()
    }
}
