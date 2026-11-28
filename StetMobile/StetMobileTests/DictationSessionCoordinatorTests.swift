import AVFoundation
import Foundation
import StetCore
import SwiftData
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
    func bootstrapCanUseEngineManagedPreparation() async throws {
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
            notificationCenter: NotificationCenter(),
            activityRecorder: NoOpDictationActivityRecorder()
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

    @Test(arguments: [false, true])
    func rewriteKeepsTranscribingSessionFreshUntilCompletionOrCancellation(cancelled: Bool) async throws {
        let rewrite = AsyncStream<String>.makeStream()
        defer { rewrite.continuation.finish() }
        let postProcessor = FakeTranscriptPostProcessor { transcript in
            var results = rewrite.stream.makeAsyncIterator()
            return await results.next() ?? transcript
        }
        let interval = Duration.milliseconds(20)
        let fixture = makeFixture(
            engine: FakeASREngine(),
            modelManager: FakeResourcePreparer(),
            commandMonitor: FakeKeyboardCommandMonitor(),
            postProcessor: postProcessor,
            rewriteHeartbeatInterval: interval
        )
        var events = fixture.coordinator.events.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)
        try await beginTranscribing(fixture, sessionId: "session-a", events: &events)

        fixture.engine.emitFinal(sessionId: "session-a", text: "original")
        guard case .rewriting(sessionId: "session-a") = try await nextEvent(&events) else {
            Issue.record("Expected rewrite to start")
            return
        }
        var staleSession = try #require(fixture.sessionStore.session)
        staleSession.updatedAt = Date().addingTimeInterval(-11)
        fixture.sessionStore.saveSession(staleSession)
        let initialHeartbeatCount = fixture.sessionStore.transcribingRefreshCount

        let deadline = ContinuousClock.now + .seconds(2)
        while fixture.sessionStore.transcribingRefreshCount < initialHeartbeatCount + 2,
            ContinuousClock.now < deadline
        {
            try await Task.sleep(for: interval)
        }

        let refreshedSession = try #require(fixture.sessionStore.session)
        #expect(fixture.sessionStore.transcribingRefreshCount >= initialHeartbeatCount + 2)
        #expect(refreshedSession.state == .transcribing)
        #expect(Date().timeIntervalSince(refreshedSession.updatedAt) < 10)
        #expect(refreshedSession.revision == staleSession.revision)

        if cancelled {
            // The keyboard can cancel the persisted session before the monitor delivers its command.
            #expect(fixture.sessionStore.updateState(for: "session-a", to: .cancelled, error: nil))
            try await Task.sleep(for: interval * 3)
            #expect(fixture.sessionStore.session?.state == .cancelled)
            rewrite.continuation.yield("rewritten")
            expectReady(try await nextEvent(&events), engineName: fixture.engine.name)
            #expect(fixture.sessionStore.session?.finalText == staleSession.finalText)
        } else {
            rewrite.continuation.yield("rewritten")
            expectCompleted(try await nextEvent(&events), sessionId: "session-a", text: "rewritten")
            #expect(fixture.sessionStore.session?.state == .ready)
            #expect(fixture.sessionStore.session?.finalText == "rewritten")
        }

        let finalSession = try #require(fixture.sessionStore.session)
        try await Task.sleep(for: interval * 3)
        #expect(fixture.sessionStore.session?.updatedAt == finalSession.updatedAt)
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

        let message = "Apple Speech stopped unexpectedly."
        fixture.engine.emitFailure(sessionId: "session-a", message: message)

        expectFailed(
            try await nextEvent(&events),
            sessionId: "session-a",
            message: message
        )
        #expect(fixture.coordinator.phase == .failed(message: message))
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
        let modelManager = FakeResourcePreparer(downloadMode: .suspended)
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
            modelManager: FakeResourcePreparer(),
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

    @Test
    func completedDictationRecordsHistoryAndIOSStatsWithoutRewrite() async throws {
        let container = try StetCloudDataContainer.makeInMemoryContainer()
        var recordedHistory: [(raw: String, llm: String?, final: String, bundleID: String?, appName: String?)] = []
        let activityRecorder = SyncedDictationActivityRecorder(
            recordHistory: { rawText, llmText, finalText, bundleID, appName, timestamp in
                recordedHistory.append((rawText, llmText, finalText, bundleID, appName))
                let context = ModelContext(container)
                context.insert(
                    HistoryEntry(
                        timestamp: timestamp,
                        rawText: rawText,
                        llmText: llmText,
                        finalText: finalText,
                        targetBundleID: bundleID,
                        targetAppName: appName,
                        status: .completed
                    )
                )
                try? context.save()
            },
            statsModel: DictationStatsModel(modelContainer: container),
            bundleIdentifier: "NaichengDeng.StetMobile",
            appName: "Stet iOS",
            asyncStatsRecording: false
        )
        let fixture = makeFixture(
            engine: FakeASREngine(),
            modelManager: FakeResourcePreparer(),
            commandMonitor: FakeKeyboardCommandMonitor(),
            activityRecorder: activityRecorder
        )
        var events = fixture.coordinator.events.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)
        try await beginTranscribing(fixture, sessionId: "session-ios-1", events: &events)

        let metrics = ASRMetrics(audioDuration: 3.5, cpuDuration: 0.2, wallDuration: 0.3, rtf: 0.08)
        fixture.engine.emitFinal(sessionId: "session-ios-1", text: "hello 世界", metrics: metrics)
        expectCompleted(try await nextEvent(&events), sessionId: "session-ios-1", text: "hello 世界")

        #expect(recordedHistory.count == 1)
        #expect(recordedHistory[0].raw == "hello 世界")
        #expect(recordedHistory[0].llm == nil)
        #expect(recordedHistory[0].final == "hello 世界")
        #expect(recordedHistory[0].bundleID == "NaichengDeng.StetMobile")
        #expect(recordedHistory[0].appName == "Stet iOS")

        let context = ModelContext(container)
        let sessions = try context.fetch(FetchDescriptor<DictationSessionRecord>())
        #expect(sessions.count == 1)
        #expect(sessions[0].sourcePlatform == "iOS")
        #expect(sessions[0].targetAppName == "Stet iOS")
        #expect(sessions[0].targetBundleID == "NaichengDeng.StetMobile")
        #expect(sessions[0].wordCount == 3)
        #expect(sessions[0].durationSeconds == 3.5)

        let historyEntries = try context.fetch(FetchDescriptor<HistoryEntry>())
        #expect(historyEntries.count == 1)
        #expect(historyEntries[0].status == .completed)

        await fixture.coordinator.shutdown()
    }

    @Test
    func completedDictationWithRewriteRecordsRawLLMAndFinalText() async throws {
        let recorder = SpyDictationActivityRecorder()
        let postProcessor = FakeTranscriptPostProcessor { _ in "Hello, world!" }
        let fixture = makeFixture(
            engine: FakeASREngine(),
            modelManager: FakeResourcePreparer(),
            commandMonitor: FakeKeyboardCommandMonitor(),
            postProcessor: postProcessor,
            activityRecorder: recorder
        )
        var events = fixture.coordinator.events.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)
        try await beginTranscribing(fixture, sessionId: "session-ios-2", events: &events)

        fixture.engine.emitFinal(sessionId: "session-ios-2", text: "uh hello world")
        guard case .rewriting(sessionId: "session-ios-2") = try await nextEvent(&events) else {
            Issue.record("Expected rewriting event")
            return
        }
        expectCompleted(try await nextEvent(&events), sessionId: "session-ios-2", text: "Hello, world!")

        #expect(recorder.records.count == 1)
        #expect(recorder.records[0].rawText == "uh hello world")
        #expect(recorder.records[0].llmText == "Hello, world!")
        #expect(recorder.records[0].finalText == "Hello, world!")
        #expect(recorder.records[0].durationSeconds >= 0)

        await fixture.coordinator.shutdown()
    }

    @Test
    func idleStandbyTimeoutSuspendsAudioClearsHeartbeatAndRecoversOnKeyboardWake() async throws {
        let engine = FakeASREngine()
        let commandMonitor = FakeKeyboardCommandMonitor(replaysLatestCommandOnForcedPoll: true)
        let fixture = makeFixture(
            engine: engine,
            modelManager: FakeResourcePreparer(),
            commandMonitor: commandMonitor,
            idleStandbyTimeout: .milliseconds(40)
        )
        var events = fixture.coordinator.events.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)

        expectStandby(try await nextEvent(&events))
        #expect(fixture.coordinator.phase == .standby)
        #expect(engine.suspendAudioCallCount == 1)
        #expect(commandMonitor.stopCallCount == 1)
        #expect(fixture.sessionStore.clearHeartbeatCallCount == 1)

        // Audio interruptions while intentionally paused must not wake the mic.
        fixture.notificationCenter.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue
            ]
        )
        try await Task.sleep(for: .milliseconds(30))
        #expect(fixture.coordinator.phase == .standby)
        #expect(engine.prepareCallCount == 1)

        // Keyboard wakes Stet with a pending start command.
        fixture.sessionStore.saveSession(makeSession(id: "session-wake", state: .requestStart))
        fixture.coordinator.synchronizeKeyboardCommands()
        expectLoading(try await nextEvent(&events))
        expectReady(try await nextEvent(&events), engineName: engine.name)
        expectStarting(try await nextEvent(&events), sessionId: "session-wake")
        expectRecording(try await nextEvent(&events), sessionId: "session-wake")
        #expect(engine.prepareCallCount == 2)
        #expect(commandMonitor.startCallCount == 2)

        await fixture.coordinator.shutdown()
    }

    @Test
    func idleStandbyTimeoutDoesNotInterruptRecordingAndRearmsAfterCompletion() async throws {
        let engine = FakeASREngine()
        let fixture = makeFixture(
            engine: engine,
            modelManager: FakeResourcePreparer(),
            commandMonitor: FakeKeyboardCommandMonitor(),
            idleStandbyTimeout: .milliseconds(50)
        )
        var events = fixture.coordinator.events.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)

        fixture.coordinator.startRecording(sessionId: "session-a")
        expectStarting(try await nextEvent(&events), sessionId: "session-a")
        expectRecording(try await nextEvent(&events), sessionId: "session-a")

        try await Task.sleep(for: .milliseconds(90))
        #expect(fixture.coordinator.phase == .recording(sessionId: "session-a"))
        #expect(engine.suspendAudioCallCount == 0)

        fixture.coordinator.stopRecording(sessionId: "session-a")
        expectTranscribing(try await nextEvent(&events), sessionId: "session-a")
        engine.emitFinal(sessionId: "session-a", text: "still recording")
        expectCompleted(try await nextEvent(&events), sessionId: "session-a", text: "still recording")

        expectStandby(try await nextEvent(&events))
        #expect(fixture.coordinator.phase == .standby)
        #expect(engine.suspendAudioCallCount == 1)

        await fixture.coordinator.shutdown()
    }

    @Test
    func updatingIdleStandbyTimeoutReschedulesOrWakesFromStandby() async throws {
        let engine = FakeASREngine()
        let fixture = makeFixture(
            engine: engine,
            modelManager: FakeResourcePreparer(),
            commandMonitor: FakeKeyboardCommandMonitor(),
            idleStandbyTimeout: nil
        )
        var events = fixture.coordinator.events.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)

        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.coordinator.phase == .idle)
        #expect(engine.suspendAudioCallCount == 0)

        fixture.coordinator.updateIdleStandbyTimeout(.milliseconds(30))
        expectStandby(try await nextEvent(&events))
        #expect(fixture.coordinator.phase == .standby)
        #expect(engine.suspendAudioCallCount == 1)

        // Switching to Never while paused wakes standby immediately.
        fixture.coordinator.updateIdleStandbyTimeout(nil)
        expectLoading(try await nextEvent(&events))
        expectReady(try await nextEvent(&events), engineName: engine.name)
        #expect(fixture.coordinator.phase == .idle)

        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.coordinator.phase == .idle)

        await fixture.coordinator.shutdown()
    }

    @Test
    func startRecordingDirectlyFromStandbyWakesAndCompletes() async throws {
        let engine = FakeASREngine()
        let fixture = makeFixture(
            engine: engine,
            modelManager: FakeResourcePreparer(),
            commandMonitor: FakeKeyboardCommandMonitor(),
            idleStandbyTimeout: .milliseconds(30)
        )
        var events = fixture.coordinator.events.makeAsyncIterator()
        try await startAndBecomeReady(fixture, events: &events)

        expectStandby(try await nextEvent(&events))
        #expect(fixture.coordinator.phase == .standby)

        fixture.coordinator.startRecording(sessionId: "session-direct")
        expectStarting(try await nextEvent(&events), sessionId: "session-direct")
        expectRecording(try await nextEvent(&events), sessionId: "session-direct")
        #expect(fixture.commandMonitor.startCallCount == 2)

        fixture.coordinator.stopRecording(sessionId: "session-direct")
        expectTranscribing(try await nextEvent(&events), sessionId: "session-direct")
        engine.emitFinal(sessionId: "session-direct", text: "woke up")
        expectCompleted(try await nextEvent(&events), sessionId: "session-direct", text: "woke up")

        await fixture.coordinator.shutdown()
    }
}

@MainActor
private func makeFixture(
    engine: FakeASREngine
) -> CoordinatorFixture {
    makeFixture(
        engine: engine,
        modelManager: FakeResourcePreparer(),
        commandMonitor: FakeKeyboardCommandMonitor()
    )
}

@MainActor
private func makeFixture(
    engine: FakeASREngine,
    modelManager: FakeResourcePreparer,
    commandMonitor: FakeKeyboardCommandMonitor,
    postProcessor: FakeTranscriptPostProcessor? = nil,
    rewriteHeartbeatInterval: Duration = .seconds(2),
    idleStandbyTimeout: Duration? = nil,
    activityRecorder: (any DictationActivityRecording)? = nil
) -> CoordinatorFixture {
    let permission = FakeMicrophonePermissionProvider()
    let sessionStore = InMemoryDictationSessionStore()
    let notificationCenter = NotificationCenter()
    commandMonitor.attach(sessionStore: sessionStore)
    let coordinator = DictationSessionCoordinator(
        engine: engine,
        prepareResources: {
            try await modelManager.downloadIfNeeded(for: "test-model")
        },
        permissionProvider: permission,
        sessionStore: sessionStore,
        postProcessor: postProcessor ?? FakeTranscriptPostProcessor(),
        commandMonitor: commandMonitor,
        notificationCenter: notificationCenter,
        rewriteHeartbeatInterval: rewriteHeartbeatInterval,
        idleStandbyTimeout: idleStandbyTimeout,
        activityRecorder: activityRecorder ?? NoOpDictationActivityRecorder()
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
    let modelManager: FakeResourcePreparer
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
    private let onStart: @MainActor () -> Void
    private let onShutdown: @MainActor () -> Void

    init(
        engineName: String,
        onStart: @escaping @MainActor () -> Void = {},
        onShutdown: @escaping @MainActor () -> Void = {}
    ) {
        self.engineName = engineName
        self.onStart = onStart
        self.onShutdown = onShutdown
        (events, continuation) = AsyncStream.makeStream()
    }

    func start() {
        startCallCount += 1
        onStart()
        phase = .idle
        continuation.yield(.ready(engineName: engineName))
    }

    func recoverAudioSession() {}
    func updateIdleStandbyTimeout(_ _: Duration?) {}
    func synchronizeKeyboardCommands() {}
    func startRecording(sessionId _: String) {}
    func stopRecording(sessionId _: String?) {}
    func cancelRecording(sessionId _: String) {}

    func shutdown() async {
        shutdownCallCount += 1
        onShutdown()
        phase = .inactive
        continuation.finish()
    }
}

@MainActor
private final class SwitchingCaptureResource {
    private(set) var activeCount = 0
    private(set) var maximumActiveCount = 0

    func acquire() {
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
    }

    func release() {
        activeCount -= 1
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

private func expectStandby(_ event: DictationCoordinatorEvent) {
    guard case .standby = event else {
        Issue.record("Expected standby event, got \(String(describing: event))")
        return
    }
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
    private(set) var suspendAudioCallCount = 0
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

    func suspendAudio() {
        suspendAudioCallCount += 1
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

    func emitFinal(sessionId: String, text: String, metrics: ASRMetrics? = nil) {
        resultContinuation.yield(
            ASRResult(sessionId: sessionId, text: text, isFinal: true, metrics: metrics)
        )
    }

    func emitFailure(sessionId: String?, message: String) {
        failureContinuation.yield(
            MobileASREngineFailure(sessionId: sessionId, message: message)
        )
    }
}

@MainActor
private final class FakeResourcePreparer {
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
    private(set) var clearHeartbeatCallCount = 0
    private(set) var transcribingRefreshCount = 0

    func heartbeat() {
        heartbeatCallCount += 1
    }

    func clearHeartbeat() {
        clearHeartbeatCallCount += 1
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
        if session.state == .transcribing, state == .transcribing {
            transcribingRefreshCount += 1
        }
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
    private let rewrite: ((String) async -> String)?

    var isAvailable: Bool { rewrite != nil }

    init(rewrite: ((String) async -> String)? = nil) {
        self.rewrite = rewrite
    }

    func process(_ transcript: String) async -> String {
        await rewrite?(transcript) ?? transcript
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

@MainActor
private final class SpyDictationActivityRecorder: DictationActivityRecording {
    struct Record: Equatable {
        let rawText: String
        let llmText: String?
        let finalText: String
        let startedAt: Date
        let completedAt: Date
        let durationSeconds: Double
    }

    private(set) var records: [Record] = []

    func recordCompletedSession(
        rawText: String,
        llmText: String?,
        finalText: String,
        startedAt: Date,
        completedAt: Date,
        durationSeconds: Double
    ) {
        records.append(
            Record(
                rawText: rawText,
                llmText: llmText,
                finalText: finalText,
                startedAt: startedAt,
                completedAt: completedAt,
                durationSeconds: durationSeconds
            )
        )
    }
}
