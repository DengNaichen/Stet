import AVFoundation
import Foundation

enum DictationCoordinatorPhase: Equatable, Sendable {
    case inactive
    case loading
    case idle
    case starting(sessionId: String)
    case recording(sessionId: String)
    case transcribing(sessionId: String)
    case rewriting(sessionId: String)
    case failed(message: String)
}

enum DictationCoordinatorEvent: Sendable {
    case loading
    case ready(engineName: String)
    case starting(sessionId: String)
    case recording(sessionId: String)
    case transcribing(sessionId: String)
    case rewriting(sessionId: String)
    case partialTranscript(sessionId: String, text: String)
    case completed(sessionId: String, text: String, metrics: ASRMetrics?)
    case failed(sessionId: String?, message: String)
}

@MainActor
protocol DictationSessionCoordinating: AnyObject {
    var events: AsyncStream<DictationCoordinatorEvent> { get }
    var phase: DictationCoordinatorPhase { get }

    func start()
    func recoverAudioSession()
    func synchronizeKeyboardCommands()
    func startRecording(sessionId: String)
    func stopRecording(sessionId: String?)
    func cancelRecording(sessionId: String)
    func shutdown()
}

@MainActor
final class DictationSessionCoordinator: DictationSessionCoordinating {
    let events: AsyncStream<DictationCoordinatorEvent>
    private(set) var phase: DictationCoordinatorPhase = .inactive

    private let continuation: AsyncStream<DictationCoordinatorEvent>.Continuation
    private let engine: any ASREngine
    private let modelManager: any ASRModelManager
    private let modelName: String
    private let permissionProvider: any MicrophonePermissionProviding
    private let sessionStore: any DictationSessionPersisting
    private let postProcessor: any TranscriptPostProcessing
    private let commandMonitor: any KeyboardCommandMonitoring
    private let notificationCenter: NotificationCenter

    private var activeSessionId: String?
    private var pendingStopSessionId: String?
    private var isStarted = false

    private var bootstrapTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var rewriteTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var commandsTask: Task<Void, Never>?
    private var audioSessionObservers: [NSObjectProtocol] = []

    init(
        engine: any ASREngine,
        modelManager: any ASRModelManager,
        modelName: String = SenseVoiceModelManager.modelName,
        permissionProvider: any MicrophonePermissionProviding,
        sessionStore: any DictationSessionPersisting,
        postProcessor: any TranscriptPostProcessing,
        commandMonitor: any KeyboardCommandMonitoring,
        notificationCenter: NotificationCenter = .default
    ) {
        self.engine = engine
        self.modelManager = modelManager
        self.modelName = modelName
        self.permissionProvider = permissionProvider
        self.sessionStore = sessionStore
        self.postProcessor = postProcessor
        self.commandMonitor = commandMonitor
        self.notificationCenter = notificationCenter
        (events, continuation) = AsyncStream.makeStream()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        listenForResults()
        listenForKeyboardCommands()
        registerAudioSessionObservers()
        commandMonitor.start()
        bootstrap()
    }

    func recoverAudioSession() {
        guard isStarted else { return }

        if case .failed = phase {
            bootstrap()
            return
        }

        guard bootstrapTask == nil, recoveryTask == nil else { return }
        recoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { recoveryTask = nil }

            do {
                try await engine.prepare()
            } catch {
                fail(sessionId: activeSessionId, message: error.localizedDescription)
            }
        }
    }

    func synchronizeKeyboardCommands() {
        commandMonitor.pollNow()
    }

    func startRecording(sessionId: String) {
        guard phase == .idle else { return }

        activeSessionId = sessionId
        pendingStopSessionId = nil
        phase = .starting(sessionId: sessionId)
        continuation.yield(.starting(sessionId: sessionId))

        startTask?.cancel()
        startTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { startTask = nil }

            do {
                try await engine.start(sessionId: sessionId)
            } catch {
                guard activeSessionId == sessionId else { return }
                activeSessionId = nil
                pendingStopSessionId = nil
                fail(sessionId: sessionId, message: error.localizedDescription)
                return
            }

            guard activeSessionId == sessionId else {
                engine.stop()
                return
            }

            if pendingStopSessionId == sessionId {
                pendingStopSessionId = nil
                engine.stop()
                markTranscribing(sessionId: sessionId)
                return
            }

            if !sessionStore.updateState(for: sessionId, to: .recording, error: nil) {
                sessionStore.saveSession(
                    DictationSession(
                        sessionId: sessionId,
                        createdAt: Date(),
                        updatedAt: Date(),
                        state: .recording
                    )
                )
            }
            phase = .recording(sessionId: sessionId)
            continuation.yield(.recording(sessionId: sessionId))
        }
    }

    func stopRecording(sessionId: String?) {
        guard let activeSessionId else { return }
        if let sessionId, sessionId != activeSessionId { return }

        switch phase {
        case .starting:
            pendingStopSessionId = activeSessionId
            phase = .transcribing(sessionId: activeSessionId)
            continuation.yield(.transcribing(sessionId: activeSessionId))

        case .recording:
            engine.stop()
            markTranscribing(sessionId: activeSessionId)

        default:
            break
        }
    }

    func cancelRecording(sessionId: String) {
        guard activeSessionId == sessionId else { return }

        activeSessionId = nil
        pendingStopSessionId = nil
        rewriteTask?.cancel()
        rewriteTask = nil
        engine.stop()
        sessionStore.updateState(for: sessionId, to: .idle, error: nil)
        phase = .idle
        continuation.yield(.ready(engineName: engine.name))
    }

    func shutdown() {
        guard isStarted else { return }
        isStarted = false

        bootstrapTask?.cancel()
        recoveryTask?.cancel()
        startTask?.cancel()
        rewriteTask?.cancel()
        resultsTask?.cancel()
        commandsTask?.cancel()
        bootstrapTask = nil
        recoveryTask = nil
        startTask = nil
        rewriteTask = nil
        resultsTask = nil
        commandsTask = nil

        commandMonitor.stop()
        for observer in audioSessionObservers {
            notificationCenter.removeObserver(observer)
        }
        audioSessionObservers.removeAll()
        engine.teardown()
        activeSessionId = nil
        pendingStopSessionId = nil
        phase = .inactive
        continuation.finish()
    }

    private func bootstrap() {
        guard bootstrapTask == nil else { return }
        phase = .loading
        continuation.yield(.loading)

        bootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { bootstrapTask = nil }

            do {
                try await permissionProvider.requestPermission()
                try await modelManager.downloadIfNeeded(for: modelName)
                try await engine.prepare()

                guard !Task.isCancelled else { return }
                phase = .idle
                continuation.yield(.ready(engineName: engine.name))
                commandMonitor.pollNow()
            } catch {
                guard !Task.isCancelled else { return }
                fail(sessionId: nil, message: error.localizedDescription)
            }
        }
    }

    private func listenForResults() {
        let resultStream = engine.resultStream
        resultsTask = Task { @MainActor [weak self] in
            for await result in resultStream {
                guard !Task.isCancelled else { break }
                self?.handle(result)
            }
        }
    }

    private func listenForKeyboardCommands() {
        let commands = commandMonitor.commands
        commandsTask = Task { @MainActor [weak self] in
            for await command in commands {
                guard !Task.isCancelled else { break }
                self?.handle(command)
            }
        }
    }

    private func handle(_ command: KeyboardDictationCommand) {
        switch command {
        case .start(let sessionId):
            startRecording(sessionId: sessionId)
        case .stop(let sessionId):
            stopRecording(sessionId: sessionId)
        case .cancel(let sessionId):
            cancelRecording(sessionId: sessionId)
        }
    }

    private func handle(_ result: ASRResult) {
        guard let sessionId = activeSessionId else { return }

        if result.isFinal {
            finalize(sessionId: sessionId, text: result.text, metrics: result.metrics)
        } else {
            sessionStore.updateText(for: sessionId, partial: result.text, final: "")
            continuation.yield(.partialTranscript(sessionId: sessionId, text: result.text))
        }
    }

    private func finalize(
        sessionId: String,
        text: String,
        metrics: ASRMetrics?
    ) {
        guard activeSessionId == sessionId else { return }

        guard !text.isEmpty else {
            complete(sessionId: sessionId, text: text, metrics: metrics)
            return
        }

        guard postProcessor.isAvailable else {
            complete(sessionId: sessionId, text: text, metrics: metrics)
            return
        }

        phase = .rewriting(sessionId: sessionId)
        continuation.yield(.rewriting(sessionId: sessionId))
        rewriteTask?.cancel()
        rewriteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { rewriteTask = nil }

            let processedText = await postProcessor.process(text)
            guard !Task.isCancelled, activeSessionId == sessionId else { return }
            complete(sessionId: sessionId, text: processedText, metrics: metrics)
        }
    }

    private func complete(
        sessionId: String,
        text: String,
        metrics: ASRMetrics?
    ) {
        guard activeSessionId == sessionId else { return }

        if !text.isEmpty {
            sessionStore.updateText(for: sessionId, partial: text, final: text)
        }
        sessionStore.updateState(for: sessionId, to: .ready, error: nil)
        activeSessionId = nil
        pendingStopSessionId = nil
        phase = .idle
        continuation.yield(.completed(sessionId: sessionId, text: text, metrics: metrics))
    }

    private func markTranscribing(sessionId: String) {
        guard activeSessionId == sessionId else { return }
        phase = .transcribing(sessionId: sessionId)
        sessionStore.updateState(for: sessionId, to: .transcribing, error: nil)
        continuation.yield(.transcribing(sessionId: sessionId))
    }

    private func fail(sessionId: String?, message: String) {
        let targetSessionId = sessionId ?? activeSharedSessionId()
        if let targetSessionId {
            sessionStore.updateState(for: targetSessionId, to: .failed, error: message)
        }
        activeSessionId = nil
        pendingStopSessionId = nil
        phase = .failed(message: message)
        continuation.yield(.failed(sessionId: sessionId, message: message))
    }

    private func activeSharedSessionId() -> String? {
        guard let session = sessionStore.getSession() else { return nil }

        switch session.state {
        case .requestStart, .launching, .warming, .recording, .requestStop, .transcribing:
            return session.sessionId
        default:
            return nil
        }
    }

    private func registerAudioSessionObservers() {
        let interruptionObserver = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let info = notification.userInfo,
                let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: typeRaw),
                type == .ended,
                let self
            else { return }
            Task { @MainActor [self] in
                self.recoverAudioSession()
            }
        }

        let resetObserver = notificationCenter.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.recoverAudioSession()
            }
        }

        audioSessionObservers = [interruptionObserver, resetObserver]
    }
}

@MainActor
final class UnavailableDictationSessionCoordinator: DictationSessionCoordinating {
    let events: AsyncStream<DictationCoordinatorEvent>
    private(set) var phase: DictationCoordinatorPhase

    private let continuation: AsyncStream<DictationCoordinatorEvent>.Continuation
    private let message: String
    private var didStart = false

    init(message: String) {
        self.message = message
        self.phase = .failed(message: message)
        (events, continuation) = AsyncStream.makeStream()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        continuation.yield(.failed(sessionId: nil, message: message))
    }

    func recoverAudioSession() {
        continuation.yield(.failed(sessionId: nil, message: message))
    }

    func synchronizeKeyboardCommands() {}
    func startRecording(sessionId _: String) {}
    func stopRecording(sessionId _: String?) {}
    func cancelRecording(sessionId _: String) {}
    func shutdown() {}
}
