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
    func shutdown() async
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
    private var isStarted = false
    private var lifecycleGeneration = UUID()
    private var bootstrapGeneration: UUID?
    private var recoveryGeneration: UUID?
    private var startGeneration: UUID?
    private var rewriteGeneration: UUID?
    private var requiresAudioEngineReset = false

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
        lifecycleGeneration = UUID()
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
        guard phase == .idle else { return }

        guard bootstrapTask == nil,
            recoveryTask == nil,
            startTask == nil
        else { return }
        let generation = UUID()
        let lifecycle = lifecycleGeneration
        recoveryGeneration = generation
        phase = .loading
        continuation.yield(.loading)
        recoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.recoveryGeneration == generation {
                    self.recoveryGeneration = nil
                    self.recoveryTask = nil
                }
            }

            do {
                try await self.prepareEngine()
                guard self.isCurrent(lifecycle: lifecycle),
                    self.recoveryGeneration == generation,
                    !Task.isCancelled
                else { return }
                self.phase = .idle
                self.continuation.yield(.ready(engineName: self.engine.name))
                self.commandMonitor.pollNow(force: true)
            } catch {
                guard self.isCurrent(lifecycle: lifecycle),
                    self.recoveryGeneration == generation,
                    !Task.isCancelled
                else { return }
                self.fail(sessionId: nil, message: error.localizedDescription)
            }
        }
    }

    func synchronizeKeyboardCommands() {
        commandMonitor.pollNow(force: true)
    }

    func startRecording(sessionId: String) {
        guard phase == .idle,
            startTask == nil,
            recoveryTask == nil,
            sessionStore.claimSessionForStart(sessionId: sessionId)
        else { return }

        activeSessionId = sessionId
        phase = .starting(sessionId: sessionId)
        continuation.yield(.starting(sessionId: sessionId))

        let generation = UUID()
        let lifecycle = lifecycleGeneration
        startGeneration = generation
        startTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.startGeneration == generation {
                    self.startGeneration = nil
                    self.startTask = nil
                    if self.shouldFinishCancelledStart(sessionId: sessionId) {
                        self.phase = .idle
                        self.continuation.yield(.ready(engineName: self.engine.name))
                    }
                    if self.phase == .idle {
                        self.commandMonitor.pollNow(force: true)
                    }
                }
            }

            do {
                try await self.engine.start(sessionId: sessionId)
            } catch {
                guard self.isCurrent(lifecycle: lifecycle),
                    self.startGeneration == generation,
                    self.activeSessionId == sessionId,
                    !Task.isCancelled
                else { return }
                self.fail(sessionId: sessionId, message: error.localizedDescription)
                return
            }

            guard self.isCurrent(lifecycle: lifecycle) else { return }
            guard self.startGeneration == generation,
                self.activeSessionId == sessionId,
                !Task.isCancelled
            else {
                self.engine.stop()
                return
            }

            self.finishStartingSession(sessionId: sessionId)
        }
    }

    func stopRecording(sessionId: String?) {
        guard let activeSessionId else {
            reconcileStopWithoutActiveSession(sessionId: sessionId)
            return
        }
        if let sessionId, sessionId != activeSessionId { return }

        switch phase {
        case .starting:
            let didTransition = sessionStore.transitionState(
                for: activeSessionId,
                from: [.requestStart],
                to: .requestStop,
                error: nil
            )
            if !didTransition {
                guard let session = sessionStore.getSession(),
                    session.sessionId == activeSessionId,
                    session.state == .requestStop
                else {
                    relinquishSession(sessionId: activeSessionId)
                    return
                }
            }
            guard self.activeSessionId == activeSessionId else {
                return
            }
            phase = .transcribing(sessionId: activeSessionId)
            continuation.yield(.transcribing(sessionId: activeSessionId))

        case .recording:
            guard markTranscribing(sessionId: activeSessionId) else { return }
            engine.stop()

        default:
            break
        }
    }

    func cancelRecording(sessionId: String) {
        guard activeSessionId == sessionId else { return }

        let isSettlingStart = startTask != nil
        activeSessionId = nil
        startTask?.cancel()
        rewriteTask?.cancel()
        rewriteGeneration = nil
        rewriteTask = nil
        engine.stop()
        guard !isSettlingStart else { return }
        phase = .idle
        continuation.yield(.ready(engineName: engine.name))
    }

    func shutdown() async {
        guard isStarted else { return }
        isStarted = false
        lifecycleGeneration = UUID()

        let tasks = [
            bootstrapTask,
            recoveryTask,
            startTask,
            rewriteTask,
            resultsTask,
            commandsTask,
        ].compactMap { $0 }

        for task in tasks {
            task.cancel()
        }

        commandMonitor.stop()
        for observer in audioSessionObservers {
            notificationCenter.removeObserver(observer)
        }
        audioSessionObservers.removeAll()
        activeSessionId = nil
        bootstrapGeneration = nil
        recoveryGeneration = nil
        startGeneration = nil
        rewriteGeneration = nil
        phase = .inactive

        for task in tasks {
            await task.value
        }

        bootstrapTask = nil
        recoveryTask = nil
        startTask = nil
        rewriteTask = nil
        resultsTask = nil
        commandsTask = nil
        engine.teardown()
        continuation.finish()
    }

    private func bootstrap() {
        guard isStarted,
            bootstrapTask == nil,
            recoveryTask == nil,
            startTask == nil
        else { return }
        phase = .loading
        continuation.yield(.loading)

        let generation = UUID()
        let lifecycle = lifecycleGeneration
        bootstrapGeneration = generation
        bootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.bootstrapGeneration == generation {
                    self.bootstrapGeneration = nil
                    self.bootstrapTask = nil
                }
            }

            do {
                try await self.permissionProvider.requestPermission()
                try await self.modelManager.downloadIfNeeded(for: self.modelName)
                try await self.prepareEngine()

                guard self.isCurrent(lifecycle: lifecycle),
                    self.bootstrapGeneration == generation,
                    !Task.isCancelled
                else { return }
                self.phase = .idle
                self.continuation.yield(.ready(engineName: self.engine.name))
                self.commandMonitor.pollNow(force: true)
            } catch {
                guard self.isCurrent(lifecycle: lifecycle),
                    self.bootstrapGeneration == generation,
                    !Task.isCancelled
                else { return }
                self.fail(sessionId: nil, message: error.localizedDescription)
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
        guard isStarted else { return }

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
        guard isStarted, activeSessionId == result.sessionId else { return }
        let sessionId = result.sessionId

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
        let generation = UUID()
        let lifecycle = lifecycleGeneration
        rewriteGeneration = generation
        rewriteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.rewriteGeneration == generation {
                    self.rewriteGeneration = nil
                    self.rewriteTask = nil
                }
            }

            let processedText = await self.postProcessor.process(text)
            guard self.isCurrent(lifecycle: lifecycle),
                self.rewriteGeneration == generation,
                !Task.isCancelled,
                self.activeSessionId == sessionId
            else { return }
            self.complete(sessionId: sessionId, text: processedText, metrics: metrics)
        }
    }

    private func complete(
        sessionId: String,
        text: String,
        metrics: ASRMetrics?
    ) {
        guard activeSessionId == sessionId else { return }
        guard
            sessionStore.completeSession(
                for: sessionId,
                from: [.recording, .requestStop, .transcribing],
                finalText: text
            )
        else {
            relinquishSession(sessionId: sessionId)
            return
        }

        activeSessionId = nil
        phase = .idle
        continuation.yield(.completed(sessionId: sessionId, text: text, metrics: metrics))
        commandMonitor.pollNow(force: true)
    }

    @discardableResult
    private func markTranscribing(sessionId: String) -> Bool {
        guard activeSessionId == sessionId else { return false }
        let didTransition = sessionStore.transitionState(
            for: sessionId,
            from: [.recording, .requestStop],
            to: .transcribing,
            error: nil
        )
        if !didTransition {
            guard let session = sessionStore.getSession(),
                session.sessionId == sessionId,
                session.state == .transcribing
            else {
                relinquishSession(sessionId: sessionId)
                return false
            }
        }

        phase = .transcribing(sessionId: sessionId)
        continuation.yield(.transcribing(sessionId: sessionId))
        return true
    }

    private func fail(sessionId: String?, message: String) {
        guard isStarted else { return }
        let targetSessionId = sessionId ?? activeSharedSessionId()
        if let targetSessionId {
            sessionStore.transitionState(
                for: targetSessionId,
                from: [.requestStart, .launching, .warming, .recording, .requestStop, .transcribing],
                to: .failed,
                error: message
            )
        }
        if activeSessionId != nil {
            engine.stop()
        }
        startTask?.cancel()
        rewriteTask?.cancel()
        rewriteTask = nil
        rewriteGeneration = nil
        activeSessionId = nil
        phase = .failed(message: message)
        continuation.yield(.failed(sessionId: sessionId, message: message))
    }

    private func finishStartingSession(sessionId: String) {
        guard activeSessionId == sessionId,
            let session = sessionStore.getSession(),
            session.sessionId == sessionId
        else {
            engine.stop()
            relinquishSession(sessionId: sessionId)
            return
        }

        switch session.state {
        case .requestStart:
            guard
                sessionStore.transitionState(
                    for: sessionId,
                    from: [.requestStart],
                    to: .recording,
                    error: nil
                )
            else {
                resolveChangedSessionAfterStart(sessionId: sessionId)
                return
            }
            phase = .recording(sessionId: sessionId)
            continuation.yield(.recording(sessionId: sessionId))

        case .requestStop:
            if markTranscribing(sessionId: sessionId) {
                engine.stop()
            }

        case .cancelled:
            engine.stop()
            relinquishSession(sessionId: sessionId)

        default:
            engine.stop()
            relinquishSession(sessionId: sessionId)
        }
    }

    private func resolveChangedSessionAfterStart(sessionId: String) {
        guard let session = sessionStore.getSession(), session.sessionId == sessionId else {
            engine.stop()
            relinquishSession(sessionId: sessionId)
            return
        }

        if session.state == .requestStop, markTranscribing(sessionId: sessionId) {
            engine.stop()
        } else {
            engine.stop()
            relinquishSession(sessionId: sessionId)
        }
    }

    private func relinquishSession(sessionId: String) {
        guard activeSessionId == sessionId else { return }
        activeSessionId = nil
        phase = .idle
        continuation.yield(.ready(engineName: engine.name))
        commandMonitor.pollNow(force: true)
    }

    private func isCurrent(lifecycle: UUID) -> Bool {
        isStarted && lifecycleGeneration == lifecycle
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
                self.handleAudioSessionInvalidation(
                    message: "The audio session was interrupted. Please try again."
                )
            }
        }

        let resetObserver = notificationCenter.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.handleAudioSessionInvalidation(
                    message: "Audio services were reset. Please try again.",
                    requiresEngineReset: true
                )
            }
        }

        audioSessionObservers = [interruptionObserver, resetObserver]
    }

    private func reconcileStopWithoutActiveSession(sessionId: String?) {
        guard let sessionId,
            sessionStore.completeSession(
                for: sessionId,
                from: [.requestStop],
                finalText: ""
            )
        else { return }
        continuation.yield(.completed(sessionId: sessionId, text: "", metrics: nil))
        if phase == .loading {
            continuation.yield(.loading)
        }
        commandMonitor.pollNow(force: true)
    }

    private func shouldFinishCancelledStart(sessionId: String) -> Bool {
        guard activeSessionId == nil else { return false }
        switch phase {
        case .starting(let phaseSessionId), .transcribing(let phaseSessionId):
            return phaseSessionId == sessionId
        default:
            return false
        }
    }

    private func prepareEngine() async throws {
        while true {
            if requiresAudioEngineReset {
                requiresAudioEngineReset = false
                do {
                    try await engine.resetAudio()
                } catch {
                    requiresAudioEngineReset = true
                    throw error
                }
            } else {
                try await engine.prepare()
            }

            guard requiresAudioEngineReset else { return }
        }
    }

    private func handleAudioSessionInvalidation(
        message: String,
        requiresEngineReset: Bool = false
    ) {
        if requiresEngineReset {
            requiresAudioEngineReset = true
        }
        if let activeSessionId {
            fail(sessionId: activeSessionId, message: message)
        } else {
            recoverAudioSession()
        }
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
    func shutdown() async {
        continuation.finish()
    }
}
