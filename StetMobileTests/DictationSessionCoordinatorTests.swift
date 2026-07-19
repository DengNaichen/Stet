import AVFoundation
import Foundation
import Testing
@testable import StetMobile

@MainActor
struct DictationSessionCoordinatorTests {
    @Test
    func bootstrapPreparesDependenciesAndBecomesReady() async throws {
        let fixture = makeFixture()
        var events = fixture.coordinator.events.makeAsyncIterator()

        fixture.coordinator.start()

        expectLoading(try await nextEvent(&events))
        expectReady(try await nextEvent(&events), engineName: fixture.engine.name)
        #expect(fixture.coordinator.phase == .idle)
        #expect(fixture.engine.prepareCallCount == 1)
        #expect(fixture.permission.requestCallCount == 1)
        #expect(fixture.modelManager.downloadCallCount == 1)
        #expect(fixture.commandMonitor.startCallCount == 1)
        #expect(fixture.commandMonitor.forcedPollCallCount == 1)

        await fixture.coordinator.shutdown()
    }

    @Test
    func selectableCoordinatorSwitchesToTheChosenIdleModel() async throws {
        let senseVoice = SwitchingChildCoordinator(engineName: "SenseVoice")
        let funASR = SwitchingChildCoordinator(engineName: "FunASR Realtime")
        let subject = SelectableDictationSessionCoordinator(selectedEngine: .senseVoice) { engine in
            switch engine {
            case .senseVoice: senseVoice
            case .funASRRealtime: funASR
            }
        }
        var events = subject.events.makeAsyncIterator()

        subject.start()
        expectLoading(try await nextEvent(&events))
        expectReady(try await nextEvent(&events), engineName: "SenseVoice")

        subject.selectEngine(.funASRRealtime)
        expectLoading(try await nextEvent(&events))
        expectReady(try await nextEvent(&events), engineName: "FunASR Realtime")

        #expect(senseVoice.shutdownCallCount == 1)
        #expect(funASR.startCallCount == 1)
        #expect(subject.phase == .idle)
        await subject.shutdown()
    }

    @Test
    func cloudEngineBootstrapDoesNotRequireModelPreparation() async throws {
        let engine = FakeASREngine()
        let permission = FakeMicrophonePermissionProvider()
        let sessionStore = InMemoryDictationSessionStore()
        let commandMonitor = FakeKeyboardCommandMonitor()
        commandMonitor.attach(sessionStore: sessionStore)
        let coordinator = DictationSessionCoordinator(
            engine: engine,
            permissionProvider: permission,
            sessionStore: sessionStore,
            postProcessor: FakeTranscriptPostProcessor(),
            commandMonitor: commandMonitor,
            notificationCenter: NotificationCenter()
        )
        var events = coordinator.events.makeAsyncIterator()

        coordinator.start()

        expectLoading(try await nextEvent(&events))
        expectReady(try await nextEvent(&events), engineName: engine.name)
        #expect(permission.requestCallCount == 1)
        #expect(engine.prepareCallCount == 1)
        await coordinator.shutdown()
    }

    @Test
    func startStopAndFinalResultCompleteTheSession() async throws {
        let fixture = makeFixture()
        var events = fixture.coordinator.events.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)

        fixture.coordinator.startRecording(sessionId: "session-a")
        expectStarting(try await nextEvent(&events), sessionId: "session-a")
        expectRecording(try await nextEvent(&events), sessionId: "session-a")
        #expect(fixture.sessionStore.session?.state == .recording)

        fixture.coordinator.stopRecording(sessionId: "session-a")
        expectTranscribing(try await nextEvent(&events), sessionId: "session-a")
        #expect(fixture.sessionStore.session?.state == .transcribing)
        #expect(fixture.engine.stopCallCount == 1)

        fixture.engine.emitFinal(sessionId: "session-a", text: "hello world")
        expectCompleted(
            try await nextEvent(&events),
            sessionId: "session-a",
            text: "hello world"
        )
        #expect(fixture.coordinator.phase == .idle)
        #expect(fixture.sessionStore.session?.state == .ready)
        #expect(fixture.sessionStore.session?.finalText == "hello world")

        await fixture.coordinator.shutdown()
    }

    @Test
    func runtimeEngineFailureFailsTheActiveSessionWithoutFallback() async throws {
        let fixture = makeFixture()
        var events = fixture.coordinator.events.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)

        fixture.coordinator.startRecording(sessionId: "session-a")
        expectStarting(try await nextEvent(&events), sessionId: "session-a")
        expectRecording(try await nextEvent(&events), sessionId: "session-a")

        fixture.engine.emitFailure(
            sessionId: "session-a",
            message: FunASRError.connectionFailed.localizedDescription
        )

        expectFailed(
            try await nextEvent(&events),
            sessionId: "session-a",
            message: FunASRError.connectionFailed.localizedDescription
        )
        #expect(
            fixture.coordinator.phase
                == .failed(message: FunASRError.connectionFailed.localizedDescription)
        )
        #expect(fixture.sessionStore.session?.state == .failed)
        #expect(fixture.engine.startedSessionIds == ["session-a"])
        await fixture.coordinator.shutdown()
    }

    @Test
    func stopWhileEngineStartIsSuspendedStopsAfterStartCompletes() async throws {
        let engine = FakeASREngine(startMode: .suspended)
        let fixture = makeFixture(engine: engine)
        var events = fixture.coordinator.events.makeAsyncIterator()
        var engineStarts = engine.startCalls.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)

        fixture.coordinator.startRecording(sessionId: "session-a")
        expectStarting(try await nextEvent(&events), sessionId: "session-a")
        #expect(await engineStarts.next() == "session-a")

        fixture.coordinator.stopRecording(sessionId: "session-a")
        expectTranscribing(try await nextEvent(&events), sessionId: "session-a")
        #expect(fixture.sessionStore.session?.state == .requestStop)

        engine.resumeStart()
        expectTranscribing(try await nextEvent(&events), sessionId: "session-a")
        #expect(fixture.sessionStore.session?.state == .transcribing)
        #expect(engine.stopCallCount == 1)

        engine.emitFinal(sessionId: "session-a", text: "finished")
        expectCompleted(
            try await nextEvent(&events),
            sessionId: "session-a",
            text: "finished"
        )

        await fixture.coordinator.shutdown()
    }

    @Test
    func monitorStopForAlreadyRequestedStopSettlesSuspendedStartOnce() async throws {
        let engine = FakeASREngine(startMode: .suspended)
        let fixture = makeFixture(engine: engine)
        var events = fixture.coordinator.events.makeAsyncIterator()
        var engineStarts = engine.startCalls.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)

        fixture.coordinator.startRecording(sessionId: "session-a")
        expectStarting(try await nextEvent(&events), sessionId: "session-a")
        #expect(await engineStarts.next() == "session-a")

        #expect(
            fixture.sessionStore.updateState(
                for: "session-a",
                to: .requestStop,
                error: nil
            ))
        fixture.commandMonitor.emit(.stop(sessionId: "session-a"))
        expectTranscribing(try await nextEvent(&events), sessionId: "session-a")
        #expect(fixture.commandMonitor.forcedPollCallCount == 1)

        engine.resumeStart()
        expectTranscribing(try await nextEvent(&events), sessionId: "session-a")
        #expect(fixture.sessionStore.session?.state == .transcribing)
        #expect(engine.stopCallCount == 1)
        #expect(fixture.commandMonitor.forcedPollCallCount == 1)

        engine.emitFinal(sessionId: "session-a", text: "finished")
        expectCompleted(
            try await nextEvent(&events),
            sessionId: "session-a",
            text: "finished"
        )
        #expect(fixture.commandMonitor.forcedPollCallCount == 2)

        await fixture.coordinator.shutdown()
    }

    @Test
    func cancelAfterStopDuringSuspendedStartReturnsIdleAndAllowsAnotherSession() async throws {
        let engine = FakeASREngine(startMode: .suspended)
        let fixture = makeFixture(engine: engine)
        var events = fixture.coordinator.events.makeAsyncIterator()
        var engineStarts = engine.startCalls.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)

        fixture.coordinator.startRecording(sessionId: "session-a")
        expectStarting(try await nextEvent(&events), sessionId: "session-a")
        #expect(await engineStarts.next() == "session-a")
        fixture.coordinator.stopRecording(sessionId: "session-a")
        expectTranscribing(try await nextEvent(&events), sessionId: "session-a")

        #expect(
            fixture.sessionStore.updateState(
                for: "session-a",
                to: .cancelled,
                error: nil
            ))
        fixture.coordinator.cancelRecording(sessionId: "session-a")
        engine.resumeStart()

        expectReady(try await nextEvent(&events), engineName: engine.name)
        #expect(fixture.coordinator.phase == .idle)
        #expect(fixture.sessionStore.session?.state == .cancelled)

        fixture.coordinator.startRecording(sessionId: "session-b")
        expectStarting(try await nextEvent(&events), sessionId: "session-b")
        #expect(await engineStarts.next() == "session-b")
        #expect(engine.startedSessionIds == ["session-a", "session-b"])

        #expect(
            fixture.sessionStore.updateState(
                for: "session-b",
                to: .cancelled,
                error: nil
            ))
        fixture.coordinator.cancelRecording(sessionId: "session-b")
        engine.resumeStart()
        expectReady(try await nextEvent(&events), engineName: engine.name)

        await fixture.coordinator.shutdown()
    }

    @Test
    func latestStopDuringSuspendedBootstrapSettlesSharedSession() async throws {
        let modelManager = FakeASRModelManager(downloadMode: .suspended)
        let fixture = makeFixture(
            engine: FakeASREngine(),
            modelManager: modelManager,
            commandMonitor: FakeKeyboardCommandMonitor()
        )
        var events = fixture.coordinator.events.makeAsyncIterator()
        var modelDownloads = modelManager.downloadCalls.makeAsyncIterator()
        fixture.sessionStore.saveSession(makeSession(id: "session-a", state: .requestStart))

        fixture.coordinator.start()
        expectLoading(try await nextEvent(&events))
        #expect(await modelDownloads.next() == "test-model")

        #expect(
            fixture.sessionStore.updateState(
                for: "session-a",
                to: .requestStop,
                error: nil
            ))
        fixture.commandMonitor.emit(.stop(sessionId: "session-a"))

        expectCompleted(
            try await nextEvent(&events),
            sessionId: "session-a",
            text: ""
        )
        expectLoading(try await nextEvent(&events))
        #expect(fixture.sessionStore.session?.state == .ready)
        #expect(fixture.engine.startedSessionIds.isEmpty)

        modelManager.resumeDownload()
        expectReady(try await nextEvent(&events), engineName: fixture.engine.name)
        #expect(fixture.coordinator.phase == .idle)
        #expect(fixture.sessionStore.session?.state == .ready)
        #expect(fixture.engine.startedSessionIds.isEmpty)

        await fixture.coordinator.shutdown()
    }

    @Test
    func startRequestedDuringSuspendedRecoveryWaitsForRecovery() async throws {
        let engine = FakeASREngine(prepareMode: .suspend(call: 2))
        let commandMonitor = FakeKeyboardCommandMonitor(replaysLatestCommandOnForcedPoll: true)
        let fixture = makeFixture(
            engine: engine,
            modelManager: FakeASRModelManager(),
            commandMonitor: commandMonitor
        )
        var events = fixture.coordinator.events.makeAsyncIterator()
        var suspendedPrepares = engine.suspendedPrepareCalls.makeAsyncIterator()
        var engineStarts = engine.startCalls.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)

        fixture.coordinator.recoverAudioSession()
        expectLoading(try await nextEvent(&events))
        #expect(await suspendedPrepares.next() == 2)

        fixture.sessionStore.saveSession(makeSession(id: "session-a", state: .requestStart))
        fixture.commandMonitor.emit(.start(sessionId: "session-a"))
        await Task.yield()
        #expect(fixture.coordinator.phase == .loading)
        #expect(engine.startedSessionIds.isEmpty)

        engine.resumePrepare(call: 2)
        expectReady(try await nextEvent(&events), engineName: engine.name)
        expectStarting(try await nextEvent(&events), sessionId: "session-a")
        #expect(await engineStarts.next() == "session-a")
        expectRecording(try await nextEvent(&events), sessionId: "session-a")
        #expect(engine.startedSessionIds == ["session-a"])

        fixture.coordinator.stopRecording(sessionId: "session-a")
        expectTranscribing(try await nextEvent(&events), sessionId: "session-a")
        engine.emitFinal(sessionId: "session-a", text: "recovered")
        expectCompleted(
            try await nextEvent(&events),
            sessionId: "session-a",
            text: "recovered"
        )

        await fixture.coordinator.shutdown()
    }

    @Test
    func mediaServicesResetUsesEngineAudioResetWhileIdle() async throws {
        let fixture = makeFixture()
        var events = fixture.coordinator.events.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)
        #expect(fixture.engine.prepareCallCount == 1)
        #expect(fixture.engine.resetAudioCallCount == 0)

        fixture.notificationCenter.post(
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )

        expectLoading(try await nextEvent(&events))
        expectReady(try await nextEvent(&events), engineName: fixture.engine.name)
        #expect(fixture.coordinator.phase == .idle)
        #expect(fixture.engine.prepareCallCount == 1)
        #expect(fixture.engine.resetAudioCallCount == 1)

        await fixture.coordinator.shutdown()
    }

    @Test
    func staleResultCannotCompleteANewerSession() async throws {
        let fixture = makeFixture()
        var events = fixture.coordinator.events.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)

        try await beginTranscribing(
            fixture,
            sessionId: "session-a",
            events: &events
        )
        fixture.engine.emitFinal(sessionId: "session-a", text: "first")
        expectCompleted(
            try await nextEvent(&events),
            sessionId: "session-a",
            text: "first"
        )

        try await beginTranscribing(
            fixture,
            sessionId: "session-b",
            events: &events
        )
        fixture.engine.emitFinal(sessionId: "session-a", text: "stale")
        fixture.engine.emitFinal(sessionId: "session-b", text: "fresh")

        expectCompleted(
            try await nextEvent(&events),
            sessionId: "session-b",
            text: "fresh"
        )
        #expect(fixture.sessionStore.session?.sessionId == "session-b")
        #expect(fixture.sessionStore.session?.finalText == "fresh")

        await fixture.coordinator.shutdown()
    }

    @Test
    func replacedSessionIsNotOverwrittenWhenSuspendedStartCompletes() async throws {
        let engine = FakeASREngine(startMode: .suspended)
        let fixture = makeFixture(engine: engine)
        var events = fixture.coordinator.events.makeAsyncIterator()
        var engineStarts = engine.startCalls.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)

        fixture.coordinator.startRecording(sessionId: "session-a")
        expectStarting(try await nextEvent(&events), sessionId: "session-a")
        #expect(await engineStarts.next() == "session-a")

        fixture.sessionStore.saveSession(makeSession(id: "session-b", state: .requestStart))
        engine.resumeStart()

        expectReady(try await nextEvent(&events), engineName: engine.name)
        #expect(fixture.coordinator.phase == .idle)
        #expect(fixture.sessionStore.session?.sessionId == "session-b")
        #expect(fixture.sessionStore.session?.state == .requestStart)
        #expect(engine.stopCallCount == 1)

        await fixture.coordinator.shutdown()
    }

    @Test
    func cancelledSessionIsNotRestoredWhenSuspendedStartCompletes() async throws {
        let engine = FakeASREngine(startMode: .suspended)
        let fixture = makeFixture(engine: engine)
        var events = fixture.coordinator.events.makeAsyncIterator()
        var engineStarts = engine.startCalls.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)

        fixture.coordinator.startRecording(sessionId: "session-a")
        expectStarting(try await nextEvent(&events), sessionId: "session-a")
        #expect(await engineStarts.next() == "session-a")
        #expect(
            fixture.sessionStore.updateState(
                for: "session-a",
                to: .cancelled,
                error: nil
            ))

        engine.resumeStart()

        expectReady(try await nextEvent(&events), engineName: engine.name)
        #expect(fixture.coordinator.phase == .idle)
        #expect(fixture.sessionStore.session?.state == .cancelled)
        #expect(engine.stopCallCount == 1)

        await fixture.coordinator.shutdown()
    }
}

@MainActor
private func makeFixture(
    engine: FakeASREngine
) -> CoordinatorFixture {
    makeFixture(
        engine: engine,
        modelManager: FakeASRModelManager(),
        commandMonitor: FakeKeyboardCommandMonitor()
    )
}

@MainActor
private func makeFixture(
    engine: FakeASREngine,
    modelManager: FakeASRModelManager,
    commandMonitor: FakeKeyboardCommandMonitor
) -> CoordinatorFixture {
    let permission = FakeMicrophonePermissionProvider()
    let sessionStore = InMemoryDictationSessionStore()
    let postProcessor = FakeTranscriptPostProcessor()
    let notificationCenter = NotificationCenter()
    commandMonitor.attach(sessionStore: sessionStore)
    let coordinator = DictationSessionCoordinator(
        engine: engine,
        prepareResources: {
            try await modelManager.downloadIfNeeded(for: "test-model")
        },
        permissionProvider: permission,
        sessionStore: sessionStore,
        postProcessor: postProcessor,
        commandMonitor: commandMonitor,
        notificationCenter: notificationCenter
    )
    return CoordinatorFixture(
        coordinator: coordinator,
        engine: engine,
        modelManager: modelManager,
        permission: permission,
        sessionStore: sessionStore,
        commandMonitor: commandMonitor,
        notificationCenter: notificationCenter
    )
}

@MainActor
private func makeFixture() -> CoordinatorFixture {
    makeFixture(engine: FakeASREngine())
}

@MainActor
private struct CoordinatorFixture {
    let coordinator: DictationSessionCoordinator
    let engine: FakeASREngine
    let modelManager: FakeASRModelManager
    let permission: FakeMicrophonePermissionProvider
    let sessionStore: InMemoryDictationSessionStore
    let commandMonitor: FakeKeyboardCommandMonitor
    let notificationCenter: NotificationCenter
}

@MainActor
private final class SwitchingChildCoordinator: DictationSessionCoordinating {
    let events: AsyncStream<DictationCoordinatorEvent>
    private(set) var phase: DictationCoordinatorPhase = .inactive
    private(set) var startCallCount = 0
    private(set) var shutdownCallCount = 0

    private let continuation: AsyncStream<DictationCoordinatorEvent>.Continuation
    private let engineName: String

    init(engineName: String) {
        self.engineName = engineName
        (events, continuation) = AsyncStream.makeStream()
    }

    func start() {
        startCallCount += 1
        phase = .idle
        continuation.yield(.ready(engineName: engineName))
    }

    func recoverAudioSession() {}
    func synchronizeKeyboardCommands() {}
    func startRecording(sessionId _: String) {}
    func stopRecording(sessionId _: String?) {}
    func cancelRecording(sessionId _: String) {}

    func shutdown() async {
        shutdownCallCount += 1
        phase = .inactive
        continuation.finish()
    }
}

@MainActor
private func startAndBecomeReady(
    _ fixture: CoordinatorFixture,
    events: inout AsyncStream<DictationCoordinatorEvent>.Iterator
) async throws {
    fixture.coordinator.start()
    expectLoading(try await nextEvent(&events))
    expectReady(try await nextEvent(&events), engineName: fixture.engine.name)
}

@MainActor
private func beginTranscribing(
    _ fixture: CoordinatorFixture,
    sessionId: String,
    events: inout AsyncStream<DictationCoordinatorEvent>.Iterator
) async throws {
    fixture.coordinator.startRecording(sessionId: sessionId)
    expectStarting(try await nextEvent(&events), sessionId: sessionId)
    expectRecording(try await nextEvent(&events), sessionId: sessionId)
    fixture.coordinator.stopRecording(sessionId: sessionId)
    expectTranscribing(try await nextEvent(&events), sessionId: sessionId)
}

private enum CoordinatorTestError: Error {
    case eventStreamEnded
}

private func nextEvent(
    _ events: inout AsyncStream<DictationCoordinatorEvent>.Iterator
) async throws -> DictationCoordinatorEvent {
    guard let event = await events.next() else {
        throw CoordinatorTestError.eventStreamEnded
    }
    return event
}

private func expectLoading(_ event: DictationCoordinatorEvent) {
    guard case .loading = event else {
        Issue.record("Expected loading event, got \(String(describing: event))")
        return
    }
}

private func expectReady(_ event: DictationCoordinatorEvent, engineName: String) {
    guard case .ready(let actualEngineName) = event else {
        Issue.record("Expected ready event, got \(String(describing: event))")
        return
    }
    #expect(actualEngineName == engineName)
}

private func expectStarting(_ event: DictationCoordinatorEvent, sessionId: String) {
    guard case .starting(let actualSessionId) = event else {
        Issue.record("Expected starting event, got \(String(describing: event))")
        return
    }
    #expect(actualSessionId == sessionId)
}

private func expectRecording(_ event: DictationCoordinatorEvent, sessionId: String) {
    guard case .recording(let actualSessionId) = event else {
        Issue.record("Expected recording event, got \(String(describing: event))")
        return
    }
    #expect(actualSessionId == sessionId)
}

private func expectTranscribing(_ event: DictationCoordinatorEvent, sessionId: String) {
    guard case .transcribing(let actualSessionId) = event else {
        Issue.record("Expected transcribing event, got \(String(describing: event))")
        return
    }
    #expect(actualSessionId == sessionId)
}

private func expectCompleted(
    _ event: DictationCoordinatorEvent,
    sessionId: String,
    text: String
) {
    guard case .completed(let actualSessionId, let actualText, _) = event else {
        Issue.record("Expected completed event, got \(String(describing: event))")
        return
    }
    #expect(actualSessionId == sessionId)
    #expect(actualText == text)
}

private func expectFailed(
    _ event: DictationCoordinatorEvent,
    sessionId: String,
    message: String
) {
    guard case .failed(let actualSessionId, let actualMessage) = event else {
        Issue.record("Expected failed event, got \(String(describing: event))")
        return
    }
    #expect(actualSessionId == sessionId)
    #expect(actualMessage == message)
}

private func makeSession(id: String, state: DictationState) -> DictationSession {
    DictationSession(
        sessionId: id,
        createdAt: Date(),
        updatedAt: Date(),
        state: state
    )
}

private final class FakeASREngine: ASREngine, MobileASREngineFailureReporting {
    enum StartMode {
        case immediate
        case suspended
    }

    enum PrepareMode {
        case immediate
        case suspend(call: Int)
    }

    let name = "Fake ASR"
    let resultStream: AsyncStream<ASRResult>
    let failureStream: AsyncStream<MobileASREngineFailure>
    let startCalls: AsyncStream<String>
    let suspendedPrepareCalls: AsyncStream<Int>

    private let resultContinuation: AsyncStream<ASRResult>.Continuation
    private let failureContinuation: AsyncStream<MobileASREngineFailure>.Continuation
    private let startCallContinuation: AsyncStream<String>.Continuation
    private let suspendedPrepareCallContinuation: AsyncStream<Int>.Continuation
    private let startMode: StartMode
    private let prepareMode: PrepareMode
    private var suspendedStartContinuation: CheckedContinuation<Void, Never>?
    private var suspendedPrepareContinuations: [Int: CheckedContinuation<Void, Never>] = [:]

    private(set) var prepareCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var resetAudioCallCount = 0
    private(set) var teardownCallCount = 0
    private(set) var startedSessionIds: [String] = []

    init(
        startMode: StartMode = .immediate,
        prepareMode: PrepareMode = .immediate
    ) {
        self.startMode = startMode
        self.prepareMode = prepareMode
        (resultStream, resultContinuation) = AsyncStream.makeStream()
        (failureStream, failureContinuation) = AsyncStream.makeStream()
        (startCalls, startCallContinuation) = AsyncStream.makeStream()
        (suspendedPrepareCalls, suspendedPrepareCallContinuation) = AsyncStream.makeStream()
    }

    func prepare() async throws {
        prepareCallCount += 1
        let call = prepareCallCount
        guard case .suspend(let suspendedCall) = prepareMode,
            suspendedCall == call
        else { return }
        suspendedPrepareCallContinuation.yield(call)
        await withCheckedContinuation { continuation in
            suspendedPrepareContinuations[call] = continuation
        }
    }

    func start(sessionId: String) async throws {
        startedSessionIds.append(sessionId)
        startCallContinuation.yield(sessionId)
        guard startMode == .suspended else { return }
        await withCheckedContinuation { continuation in
            suspendedStartContinuation = continuation
        }
    }

    func stop() {
        stopCallCount += 1
    }

    func resetAudio() async throws {
        resetAudioCallCount += 1
    }

    func teardown() {
        teardownCallCount += 1
        resultContinuation.finish()
        failureContinuation.finish()
        startCallContinuation.finish()
        suspendedPrepareCallContinuation.finish()
    }

    func resumeStart() {
        suspendedStartContinuation?.resume()
        suspendedStartContinuation = nil
    }

    func resumePrepare(call: Int) {
        suspendedPrepareContinuations.removeValue(forKey: call)?.resume()
    }

    func emitFinal(sessionId: String, text: String) {
        resultContinuation.yield(
            ASRResult(sessionId: sessionId, text: text, isFinal: true)
        )
    }

    func emitFailure(sessionId: String?, message: String) {
        failureContinuation.yield(
            MobileASREngineFailure(sessionId: sessionId, message: message)
        )
    }
}

@MainActor
private final class FakeASRModelManager: ASRModelManager {
    enum DownloadMode {
        case immediate
        case suspended
    }

    let downloadCalls: AsyncStream<String>

    private let downloadCallContinuation: AsyncStream<String>.Continuation
    private let downloadMode: DownloadMode
    private var suspendedDownloadContinuation: CheckedContinuation<Void, Never>?
    private(set) var downloadCallCount = 0

    init(downloadMode: DownloadMode = .immediate) {
        self.downloadMode = downloadMode
        (downloadCalls, downloadCallContinuation) = AsyncStream.makeStream()
    }

    func status(for _: String) async -> ASRModelStatus {
        .notDownloaded
    }

    func resolveModelURLs(for _: String) async throws -> [String: URL] {
        [:]
    }

    func downloadIfNeeded(for modelName: String) async throws {
        downloadCallCount += 1
        downloadCallContinuation.yield(modelName)
        guard downloadMode == .suspended else { return }
        await withCheckedContinuation { continuation in
            suspendedDownloadContinuation = continuation
        }
    }

    func resumeDownload() {
        suspendedDownloadContinuation?.resume()
        suspendedDownloadContinuation = nil
    }
}

private final class FakeMicrophonePermissionProvider: MicrophonePermissionProviding, @unchecked Sendable {
    private(set) var requestCallCount = 0

    func requestPermission() async throws {
        requestCallCount += 1
    }
}

private final class InMemoryDictationSessionStore: DictationSessionPersisting {
    private(set) var session: DictationSession?
    private(set) var heartbeatCallCount = 0

    func heartbeat() {
        heartbeatCallCount += 1
    }

    func getSession() -> DictationSession? {
        session
    }

    func claimSessionForStart(sessionId: String) -> Bool {
        if let session {
            if session.sessionId == sessionId {
                return session.state == .requestStart
            }
            guard !isActive(session.state) else { return false }
        }

        saveSession(makeSession(id: sessionId, state: .requestStart))
        return true
    }

    func saveSession(_ session: DictationSession) {
        self.session = session
    }

    func updateState(
        for sessionId: String,
        to state: DictationState,
        error: String?
    ) -> Bool {
        guard var session, session.sessionId == sessionId else { return false }
        session.state = state
        session.updatedAt = Date()
        session.error = error
        self.session = session
        return true
    }

    func transitionState(
        for sessionId: String,
        from expectedStates: [DictationState],
        to state: DictationState,
        error: String?
    ) -> Bool {
        guard var session,
            session.sessionId == sessionId,
            expectedStates.contains(session.state)
        else { return false }
        session.state = state
        session.updatedAt = Date()
        session.error = error
        self.session = session
        return true
    }

    func updateText(
        for sessionId: String,
        partial: String,
        final: String
    ) -> Bool {
        guard var session, session.sessionId == sessionId else { return false }
        session.partialText = partial
        session.finalText = final
        session.revision += 1
        session.updatedAt = Date()
        self.session = session
        return true
    }

    func completeSession(
        for sessionId: String,
        from expectedStates: [DictationState],
        finalText: String
    ) -> Bool {
        guard var session,
            session.sessionId == sessionId,
            expectedStates.contains(session.state)
        else { return false }
        session.partialText = finalText
        session.finalText = finalText
        session.revision += 1
        session.state = .ready
        session.updatedAt = Date()
        session.error = nil
        self.session = session
        return true
    }

    private func isActive(_ state: DictationState) -> Bool {
        switch state {
        case .requestStart, .launching, .warming, .recording, .requestStop, .transcribing:
            true
        default:
            false
        }
    }
}

@MainActor
private final class FakeTranscriptPostProcessor: TranscriptPostProcessing {
    let isAvailable = false

    func process(_ transcript: String) async -> String {
        transcript
    }
}

@MainActor
private final class FakeKeyboardCommandMonitor: KeyboardCommandMonitoring {
    let commands: AsyncStream<KeyboardDictationCommand>

    private let continuation: AsyncStream<KeyboardDictationCommand>.Continuation
    private let replaysLatestCommandOnForcedPoll: Bool
    private weak var sessionStore: InMemoryDictationSessionStore?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var forcedPollCallCount = 0

    init(replaysLatestCommandOnForcedPoll: Bool = false) {
        self.replaysLatestCommandOnForcedPoll = replaysLatestCommandOnForcedPoll
        (commands, continuation) = AsyncStream.makeStream()
    }

    func attach(sessionStore: InMemoryDictationSessionStore) {
        self.sessionStore = sessionStore
    }

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
        continuation.finish()
    }

    func pollNow(force: Bool) {
        if force {
            forcedPollCallCount += 1
        }
        guard force, replaysLatestCommandOnForcedPoll,
            let session = sessionStore?.session
        else { return }
        switch session.state {
        case .requestStart:
            emit(.start(sessionId: session.sessionId))
        case .requestStop:
            emit(.stop(sessionId: session.sessionId))
        case .cancelled:
            emit(.cancel(sessionId: session.sessionId))
        default:
            break
        }
    }

    func emit(_ command: KeyboardDictationCommand) {
        continuation.yield(command)
    }
}
