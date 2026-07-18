import Foundation

enum KeyboardDictationCommand: Equatable, Sendable {
    case start(sessionId: String)
    case stop(sessionId: String)
    case cancel(sessionId: String)
}

@MainActor
protocol KeyboardCommandMonitoring: AnyObject {
    var commands: AsyncStream<KeyboardDictationCommand> { get }

    func start()
    func stop()
    func pollNow()
}

@MainActor
final class SharedKeyboardCommandMonitor: KeyboardCommandMonitoring {
    let commands: AsyncStream<KeyboardDictationCommand>

    private let continuation: AsyncStream<KeyboardDictationCommand>.Continuation
    private let sessionStore: any DictationSessionPersisting
    private let interval: TimeInterval
    private var timer: Timer?

    init(
        sessionStore: any DictationSessionPersisting,
        interval: TimeInterval = 0.15
    ) {
        self.sessionStore = sessionStore
        self.interval = interval
        (commands, continuation) = AsyncStream.makeStream()
    }

    func start() {
        guard timer == nil else { return }
        pollNow()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.pollNow()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pollNow() {
        sessionStore.heartbeat()
        guard let session = sessionStore.getSession() else { return }

        switch session.state {
        case .requestStart:
            continuation.yield(.start(sessionId: session.sessionId))
        case .requestStop:
            continuation.yield(.stop(sessionId: session.sessionId))
        case .cancelled:
            continuation.yield(.cancel(sessionId: session.sessionId))
        default:
            break
        }
    }
}
