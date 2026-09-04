import Darwin
import Foundation

// Swift imports both `struct flock` and `flock(2)` under the same Darwin
// member name. Give the public POSIX function an unambiguous Swift name.
@_silgen_name("flock")
private func stetAdvisoryFlock(_ fileDescriptor: Int32, _ operation: Int32) -> Int32

enum DictationState: String, Codable, Equatable {
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

enum DictationSessionOrigin: String, Codable, Equatable {
    case app
    case keyboard
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
    var origin: DictationSessionOrigin?
}

class SharedDictationManager {
    static let shared = SharedDictationManager()

    private struct SessionStorageContext {
        let sessionFileURL: URL?
        let permitsWrites: Bool
    }

    private let appGroupIdentifier = "group.NaichengDeng.StetMobile"
    private let sessionKey = "dictation.session"
    private let heartbeatKey = "dictation.heartbeat"
    private let pendingKey = "dictation.pending_keyboard_session_id"
    private let sessionFileName = "dictation_session.json"
    private let sessionLockFileName = "dictation_session.lock"
    private let processSessionLock = NSLock()
    private let defaults = UserDefaults(suiteName: "group.NaichengDeng.StetMobile")

    func heartbeat() {
        defaults?.set(Date().timeIntervalSince1970, forKey: heartbeatKey)
    }

    func mainAppAlive(within seconds: TimeInterval) -> Bool {
        guard let ts = defaults?.object(forKey: heartbeatKey) as? TimeInterval, ts > 0 else {
            return false
        }
        return Date().timeIntervalSince1970 - ts < seconds
    }

    func getSession() -> DictationSession? {
        withSessionTransaction { storage in
            loadSessionUnlocked(storage: storage)
        }
    }

    @discardableResult
    func claimSessionForStart(sessionId: String) -> Bool {
        withSessionTransaction { storage in
            guard storage.permitsWrites else { return false }
            if let session = loadSessionUnlocked(storage: storage) {
                if session.sessionId == sessionId {
                    return session.state == .requestStart
                }
                guard !blocksForeignClaimUnlocked(session) else { return false }
            }

            let now = Date()
            let session = DictationSession(
                sessionId: sessionId,
                createdAt: now,
                updatedAt: now,
                state: .requestStart,
                origin: .app
            )
            return persistSessionUnlocked(session, storage: storage)
        }
    }

    @discardableResult
    func beginKeyboardSession(sessionId: String) -> Bool {
        withSessionTransaction { storage in
            if var session = loadSessionUnlocked(storage: storage) {
                if session.sessionId == sessionId {
                    guard session.state == .requestStart, session.origin != .app else {
                        return false
                    }
                    session.origin = .keyboard
                    guard persistSessionUnlocked(session, storage: storage) else {
                        return false
                    }
                    savePendingKeyboardSessionIdUnlocked(sessionId)
                    return true
                }
                guard !blocksForeignClaimUnlocked(session) else { return false }
            }

            let now = Date()
            let session = DictationSession(
                sessionId: sessionId,
                createdAt: now,
                updatedAt: now,
                state: .requestStart,
                origin: .keyboard
            )
            guard persistSessionUnlocked(session, storage: storage) else { return false }
            savePendingKeyboardSessionIdUnlocked(sessionId)
            return true
        }
    }

    @discardableResult
    func updateState(
        for sessionId: String,
        to state: DictationState,
        error: String? = nil
    ) -> Bool {
        mutateSession(for: sessionId) { session in
            session.state = state
            session.updatedAt = Date()
            session.error = error
            return true
        }
    }

    @discardableResult
    func transitionState(
        for sessionId: String,
        from expectedStates: [DictationState],
        to state: DictationState,
        error: String? = nil
    ) -> Bool {
        mutateSession(for: sessionId) { session in
            guard expectedStates.contains(session.state) else { return false }
            session.state = state
            session.updatedAt = Date()
            session.error = error
            return true
        }
    }

    @discardableResult
    func updateText(
        for sessionId: String,
        partial: String,
        final: String
    ) -> Bool {
        mutateSession(for: sessionId) { session in
            session.partialText = partial
            session.finalText = final
            session.revision += 1
            session.updatedAt = Date()
            return true
        }
    }

    @discardableResult
    func completeSession(
        for sessionId: String,
        from expectedStates: [DictationState],
        finalText: String
    ) -> Bool {
        mutateSession(for: sessionId) { session in
            guard expectedStates.contains(session.state) else { return false }
            if !finalText.isEmpty {
                session.partialText = finalText
                session.finalText = finalText
                session.revision += 1
            }
            session.state = .ready
            session.updatedAt = Date()
            session.error = nil
            return true
        }
    }

    // MARK: - Pending Keyboard Session ID

    func savePendingKeyboardSessionId(_ sessionId: String) {
        withSessionTransaction { storage in
            guard storage.permitsWrites else { return }
            savePendingKeyboardSessionIdUnlocked(sessionId)
        }
    }

    func getPendingKeyboardSessionId() -> String? {
        withSessionTransaction { _ in
            defaults?.string(forKey: pendingKey)
        }
    }

    func clearPendingKeyboardSessionId(ifMatching sessionId: String) {
        withSessionTransaction { storage in
            guard storage.permitsWrites,
                defaults?.string(forKey: pendingKey) == sessionId
            else { return }
            defaults?.removeObject(forKey: pendingKey)
            defaults?.synchronize()
        }
    }

    // MARK: - Volume Sync

    private var volumeURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )?.appendingPathComponent("mic_volume.dat")
    }

    func updateVolume(_ level: Float) {
        guard let url = volumeURL else { return }
        var data = level
        let dataBytes = Data(bytes: &data, count: MemoryLayout<Float>.size)
        try? dataBytes.write(to: url)
    }

    func readVolume() -> Float {
        guard let url = volumeURL,
            let data = try? Data(contentsOf: url),
            data.count == MemoryLayout<Float>.size
        else { return 0 }
        return data.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
    }

    // MARK: - Session Transaction Internals

    private func mutateSession(
        for sessionId: String? = nil,
        _ mutation: (inout DictationSession) -> Bool
    ) -> Bool {
        withSessionTransaction { storage in
            guard var session = loadSessionUnlocked(storage: storage) else { return false }
            if let sessionId, session.sessionId != sessionId { return false }
            guard mutation(&session) else { return false }
            return persistSessionUnlocked(session, storage: storage)
        }
    }

    private func withSessionTransaction<T>(
        _ operation: (SessionStorageContext) -> T
    ) -> T {
        processSessionLock.lock()
        defer { processSessionLock.unlock() }

        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            )
        else {
            return operation(
                SessionStorageContext(sessionFileURL: nil, permitsWrites: true)
            )
        }

        let lockURL = containerURL.appendingPathComponent(sessionLockFileName)
        let fileDescriptor = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard fileDescriptor >= 0 else {
            return operation(
                SessionStorageContext(sessionFileURL: nil, permitsWrites: false)
            )
        }
        defer { _ = Darwin.close(fileDescriptor) }

        guard stetAdvisoryFlock(fileDescriptor, LOCK_EX) == 0 else {
            return operation(
                SessionStorageContext(sessionFileURL: nil, permitsWrites: false)
            )
        }
        defer { _ = stetAdvisoryFlock(fileDescriptor, LOCK_UN) }

        return operation(
            SessionStorageContext(
                sessionFileURL: containerURL.appendingPathComponent(sessionFileName),
                permitsWrites: true
            )
        )
    }

    private func loadSessionUnlocked(storage: SessionStorageContext) -> DictationSession? {
        if let fileURL = storage.sessionFileURL,
            let data = try? Data(contentsOf: fileURL),
            let session = try? JSONDecoder().decode(DictationSession.self, from: data)
        {
            return session
        }

        // A valid App Group with an unavailable lock must not fall back to a
        // potentially stale UserDefaults mirror. The mirror is only for migration
        // or environments where the App Group container itself is unavailable.
        guard storage.permitsWrites else { return nil }
        guard let mirroredData = defaults?.data(forKey: sessionKey),
            let session = try? JSONDecoder().decode(
                DictationSession.self,
                from: mirroredData
            )
        else {
            return nil
        }

        if storage.permitsWrites,
            let fileURL = storage.sessionFileURL,
            let encoded = try? JSONEncoder().encode(session)
        {
            try? encoded.write(to: fileURL, options: .atomic)
        }
        return session
    }

    private func persistSessionUnlocked(
        _ session: DictationSession,
        storage: SessionStorageContext
    ) -> Bool {
        guard storage.permitsWrites else { return false }
        guard let data = try? JSONEncoder().encode(session) else { return false }

        if let fileURL = storage.sessionFileURL {
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                return false
            }
        } else if defaults == nil {
            return false
        }

        mirrorSessionDataUnlocked(data)
        return true
    }

    private func mirrorSessionDataUnlocked(_ data: Data) {
        defaults?.set(data, forKey: sessionKey)
        defaults?.synchronize()
    }

    private func savePendingKeyboardSessionIdUnlocked(_ sessionId: String) {
        defaults?.set(sessionId, forKey: pendingKey)
        defaults?.synchronize()
    }

    private func blocksForeignClaimUnlocked(_ session: DictationSession) -> Bool {
        switch session.state {
        case .requestStart, .launching, .warming, .recording, .requestStop, .transcribing:
            return true
        case .ready:
            if session.origin == .keyboard { return true }
            return session.origin == nil
                && defaults?.string(forKey: pendingKey) == session.sessionId
        default:
            return false
        }
    }
}
