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
    func pollNow(force: Bool)
}

@MainActor
final class SharedKeyboardCommandMonitor: KeyboardCommandMonitoring {
    let commands: AsyncStream<KeyboardDictationCommand>

    private let continuation: AsyncStream<KeyboardDictationCommand>.Continuation
    private let sessionStore: any DictationSessionPersisting
    private let interval: TimeInterval
    private let retryInterval: TimeInterval
    private var timer: Timer?
    private var lastObservation: Observation?
    private var lastCommandDeliveryAt: Date?

    private struct Observation: Equatable {
        let sessionId: String
        let state: DictationState
        let revision: Int

        var isCommand: Bool {
            switch state {
            case .requestStart, .requestStop, .cancelled:
                true
            default:
                false
            }
        }
    }

    init(
        sessionStore: any DictationSessionPersisting,
        interval: TimeInterval = 0.15,
        retryInterval: TimeInterval = 1
    ) {
        self.sessionStore = sessionStore
        self.interval = interval
        self.retryInterval = retryInterval
        (commands, continuation) = AsyncStream.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    func start() {
        guard timer == nil else { return }
        pollNow(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.pollNow(force: false)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pollNow(force: Bool) {
        sessionStore.heartbeat()
        guard let session = sessionStore.getSession() else { return }

        let observation = Observation(
            sessionId: session.sessionId,
            state: session.state,
            revision: session.revision
        )
        if !force, observation == lastObservation {
            guard observation.isCommand,
                Date().timeIntervalSince(lastCommandDeliveryAt ?? .distantPast) >= retryInterval
            else { return }
        }
        lastObservation = observation

        switch session.state {
        case .requestStart:
            lastCommandDeliveryAt = Date()
            continuation.yield(.start(sessionId: session.sessionId))
        case .requestStop:
            lastCommandDeliveryAt = Date()
            continuation.yield(.stop(sessionId: session.sessionId))
        case .cancelled:
            lastCommandDeliveryAt = Date()
            continuation.yield(.cancel(sessionId: session.sessionId))
        default:
            lastCommandDeliveryAt = nil
            break
        }
    }
}
