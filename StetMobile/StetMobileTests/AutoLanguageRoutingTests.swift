import Foundation
import StetCore
import Testing
@testable import StetMobile

struct AutoLanguageRoutingTests {

    // MARK: - 1. Fbank & Prefix Activity Detector

    @Test func speechBrainFbankProducesExpectedShapeAndZeroMeanAfterCMN() {
        let fbank = SpeechBrainFbank()
        // 1.0 second of 440 Hz sine wave at 16 kHz -> (16000 + 400 - 400)/160 + 1 = 101 frames
        let sampleCount = 16_000
        let samples: [Float] = (0..<sampleCount).map { index in
            0.25 * sin(2.0 * Float.pi * 440.0 * Float(index) / 16_000.0)
        }

        let (frameCount, features) = fbank.compute(samples: samples, applySentenceMeanNormalization: true)
        #expect(frameCount == 101)
        #expect(features.count == frameCount * SpeechBrainFbank.nMels)

        // Verify each mel bin has ~0 mean across frames after sentence mean normalization.
        for melIndex in 0..<SpeechBrainFbank.nMels {
            var sum: Float = 0
            for frameIndex in 0..<frameCount {
                sum += features[frameIndex * SpeechBrainFbank.nMels + melIndex]
            }
            let mean = sum / Float(frameCount)
            #expect(abs(mean) < 1e-4)
        }
    }

    @Test func prefixActivityDetectorSkipsLeadingSilenceAndCountsActiveSpeech() {
        let detector = SpeechPrefixActivityDetector()
        let silence = [Float](repeating: 0.0005, count: 16_000)  // 1.0s silence
        let speech: [Float] = (0..<12_800).map { index in  // 0.8s speech
            0.15 * sin(2.0 * Float.pi * 300.0 * Float(index) / 16_000.0)
        }
        let combined = silence + speech

        let (window, activity) = detector.extractLIDWindow(from: combined, maxWindowSamples: 24_000)
        // Onset should be near 1.0s minus 20ms lead-in (15_680 samples).
        #expect(activity.onsetSampleIndex >= 15_000)
        #expect(activity.onsetSampleIndex <= 16_000)
        #expect(activity.activeSpeechSeconds >= 0.70)
        #expect(activity.activeSpeechSeconds <= 0.85)
        #expect(window.count >= 12_800)
        // Original buffer is untouched.
        #expect(combined.count == 28_800)

        // Continuous speech from sample 0 (no silence) must still register as active speech.
        let continuousSpeech = [Float](repeating: 0.15, count: 16_000)
        let continuousActivity = detector.analyze(samples: continuousSpeech)
        #expect(continuousActivity.activeSpeechSeconds >= 0.95)

        // Steady moderate fan noise without speech must register 0 active speech.
        let fanNoise = [Float](repeating: 0.025, count: 16_000)
        let noiseActivity = detector.analyze(samples: fanNoise)
        #expect(noiseActivity.activeSpeechSeconds == 0)
    }

    // MARK: - 2. Dual-Gate Language Routing Policy

    @Test func routingPolicyRejectsLowCandidateMassEvenWhenTwoWayRatioIsHigh() {
        let policy = LanguageRoutingPolicy.default
        // Noise or third language: P_107(en) = 0.009, P_107(zh) = 0.0001 -> naive 2-way P(en) = 98.9%,
        // but total pair mass = 0.0091 < 0.02 -> MUST stay on primary!
        let scores = SpokenLanguageScores(
            logProbabilitiesByCode: ["en": log(0.009), "zh": log(0.0001)],
            fbankMs: 0.2,
            inferenceMs: 5.0
        )

        let early = policy.evaluate(
            primary: .chineseSimplified,
            secondary: .englishUS,
            scores: scores,
            activeSpeechSeconds: 1.0,
            isFinalWindow: false
        )
        #expect(early == nil)

        let final = policy.evaluate(
            primary: .chineseSimplified,
            secondary: .englishUS,
            scores: scores,
            activeSpeechSeconds: 1.5,
            isFinalWindow: true
        )
        #expect(final?.selectedLanguage == .chineseSimplified)
        #expect(final?.reason == .lowCandidateMassFallback)
    }

    @Test func routingPolicyEnforcesAsymmetricBiasForCodeSwitchingAndAllowsShortEnglishStop() {
        let policy = LanguageRoutingPolicy.default

        // Code-switched Chinese with English words: P(en|pair)=0.78 (< 0.85) -> stays zh-CN.
        let mixedScores = SpokenLanguageScores(
            logProbabilitiesByCode: ["en": log(0.78), "zh": log(0.22)],
            fbankMs: 0.2,
            inferenceMs: 5.0
        )
        let mixedDecision = policy.evaluate(
            primary: .chineseSimplified,
            secondary: .englishUS,
            scores: mixedScores,
            activeSpeechSeconds: 1.5,
            isFinalWindow: true
        )
        #expect(mixedDecision?.selectedLanguage == .chineseSimplified)
        #expect(mixedDecision?.reason == .finalPrimary)

        // Pure English 1.0s with extreme confidence -> early locks en-US.
        let strongEnglish = SpokenLanguageScores(
            logProbabilitiesByCode: ["en": log(0.96), "zh": log(0.01)],
            fbankMs: 0.2,
            inferenceMs: 5.0
        )
        let earlyLock = policy.evaluate(
            primary: .chineseSimplified,
            secondary: .englishUS,
            scores: strongEnglish,
            activeSpeechSeconds: 1.0,
            isFinalWindow: false
        )
        #expect(earlyLock?.selectedLanguage == .englishUS)
        #expect(earlyLock?.reason == .earlyLockSecondary)

        // Short English command ("Submit", 0.6s) when user stops early -> still routes en-US!
        let shortEnglish = SpokenLanguageScores(
            logProbabilitiesByCode: ["en": log(0.30), "zh": log(0.001)],
            fbankMs: 0.1,
            inferenceMs: 4.0
        )
        let shortDecision = policy.evaluate(
            primary: .chineseSimplified,
            secondary: .englishUS,
            scores: shortEnglish,
            activeSpeechSeconds: 0.6,
            isFinalWindow: true
        )
        #expect(shortDecision?.selectedLanguage == .englishUS)
        #expect(shortDecision?.reason == .finalSecondary)

        // Same VoxLingua family (zh-CN + zh-TW) -> immediate bypass.
        let sameFamily = policy.evaluate(
            primary: .chineseSimplified,
            secondary: .chineseTraditional,
            scores: strongEnglish,
            activeSpeechSeconds: 1.5,
            isFinalWindow: true
        )
        #expect(sameFamily?.selectedLanguage == .chineseSimplified)
        #expect(sameFamily?.reason == .sameIdentifierBypass)
    }

    // MARK: - 3. Single-Cursor Bounded Audio FIFO

    @Test func fifoPreservesExactSampleOrderDropsLateCallbacksAndEnforcesBacklogCap() async throws {
        let fifo = AudioSessionFIFO(maxUnconsumedSamples: 100, maxPrefixRetainedSamples: 50)
        #expect(fifo.append([0, 1, 2, 3, 4]))
        #expect(fifo.append([5, 6, 7, 8, 9]))
        fifo.sealEnd()
        // Late callback after sealEnd must be rejected.
        #expect(!fifo.append([10, 11]))

        var drained: [Float] = []
        while let chunk = try await fifo.nextChunk(maxSamples: 3) {
            drained.append(contentsOf: chunk)
        }
        #expect(drained == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])

        // Overflow test.
        let bounded = AudioSessionFIFO(maxUnconsumedSamples: 8, maxPrefixRetainedSamples: 8)
        #expect(bounded.append([1, 2, 3, 4]))
        #expect(!bounded.append([5, 6, 7, 8, 9]))
        do {
            _ = try await bounded.nextChunk(maxSamples: 4)
            Issue.record("Expected backlogExceeded error")
        } catch let error as AudioSessionFIFO.FIFOError {
            #expect(error == .backlogExceeded)
        }
    }

    // MARK: - 4. Settings Store Secondary Language Persistence

    @MainActor
    @Test func secondaryLanguagePersistsAndClearsWhenPrimaryChangesToEnglish() throws {
        let suiteName = "AutoLanguageRoutingSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SpeechRecognitionSettingsStore(defaults: defaults)
        store.selectedLanguage = .chineseSimplified
        store.secondaryLanguage = .englishUS

        let reloaded = SpeechRecognitionSettingsStore(defaults: defaults)
        #expect(reloaded.selectedLanguage == .chineseSimplified)
        #expect(reloaded.secondaryLanguage == .englishUS)

        // Switching primary to English must automatically clear secondary to avoid zh/en duplicate.
        reloaded.selectedLanguage = .englishUS
        #expect(reloaded.secondaryLanguage == nil)
    }

    // MARK: - 5. Engine Streaming, Routing, Cancel, and Serialized Handoff

    @MainActor
    @Test func singleLanguageModeBypassesLIDAndPreservesAllOrderedSamples() async throws {
        let suiteName = "EngineSingleLangTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let capture = FakeCapture()
        let backend = FakeRecognitionBackend(finalTextByLocale: ["zh-CN": "你好世界"])
        let lid = FakeLanguageIdentifier(
            scores: SpokenLanguageScores(logProbabilitiesByCode: ["en": 0, "zh": -10], fbankMs: 0.1, inferenceMs: 1.0))

        let engine = AppleSpeechDictationEngine(
            settingsStore: SpeechRecognitionSettingsStore(defaults: defaults),
            audioCapture: capture,
            recognitionBackend: backend,
            languageIdentifier: lid,
            routingTargetsResolver: { _ in
                SpeechRecognitionSettingsStore.PreparedRoutingTargets(
                    primary: .init(
                        language: .chineseSimplified, locale: Locale(identifier: "zh-CN"), backend: .speechTranscriber),
                    secondary: nil,
                    backend: .speechTranscriber
                )
            }
        )

        var results = engine.resultStream.makeAsyncIterator()
        try await engine.start(sessionId: "s-single")

        // Feed numbered samples 0..<4800 across 3 frames.
        for batch in 0..<3 {
            let base = batch * 1_600
            let samples = (0..<1_600).map { Float(base + $0) }
            capture.emit(samples: samples, level: 0.5)
        }
        engine.stop()

        let final = try #require(await nextFinalResult(&results))
        #expect(final.sessionId == "s-single")
        #expect(final.text == "你好世界")
        #expect(lid.identifyCallCount == 0)
        #expect(backend.createdLocales == ["zh-CN"])
        let fed = backend.sessions[0].fedSamples
        #expect(fed.count == 4_800)
        #expect(fed.first == 0)
        #expect(fed.last == 4_799)
        #expect(engine.routingTelemetry(for: "s-single")?.routingReason == .singleLanguageBypass)
        engine.teardown()
    }

    @MainActor
    @Test func autoLIDRoutesToEnglishAndDeliversBufferedAndLiveSamplesInOrder() async throws {
        let suiteName = "EngineAutoLIDEnglishTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let capture = FakeCapture()
        let backend = FakeRecognitionBackend(finalTextByLocale: ["en-US": "hello from auto route"])
        let lid = FakeLanguageIdentifier(
            scores: SpokenLanguageScores(
                logProbabilitiesByCode: ["en": log(0.98), "zh": log(0.005)],
                fbankMs: 0.2,
                inferenceMs: 5.0
            )
        )

        let engine = AppleSpeechDictationEngine(
            settingsStore: SpeechRecognitionSettingsStore(defaults: defaults),
            audioCapture: capture,
            recognitionBackend: backend,
            languageIdentifier: lid,
            configuration: .init(
                routingPolicy: .default,
                maxUnconsumedSamples: 16_000 * 10,
                firstFrameTimeout: .seconds(2),
                lidStopBudget: .milliseconds(300),
                analyzerStartTimeout: .seconds(2),
                volumeThrottleInterval: .milliseconds(10)
            ),
            routingTargetsResolver: { _ in
                SpeechRecognitionSettingsStore.PreparedRoutingTargets(
                    primary: .init(
                        language: .chineseSimplified, locale: Locale(identifier: "zh-CN"), backend: .speechTranscriber),
                    secondary: .init(
                        language: .englishUS, locale: Locale(identifier: "en-US"), backend: .speechTranscriber),
                    backend: .speechTranscriber
                )
            }
        )

        var results = engine.resultStream.makeAsyncIterator()
        try await engine.start(sessionId: "s-en")

        // Emit 1.2s of active speech (> 1.0s early lock) with tagged amplitudes encoding sample index.
        let totalSamples = 19_200
        let frameSize = 1_600
        for offset in stride(from: 0, to: totalSamples, by: frameSize) {
            let samples: [Float] = (0..<frameSize).map { i in
                let idx = offset + i
                // High-energy speech wave with unique monotone offset encoding sample identity.
                return 0.2 + Float(idx) * 1e-6
            }
            capture.emit(samples: samples, level: 0.6)
        }

        // Wait until LID runs and backend session is created, then stream 0.2s more live audio.
        let deadline = ContinuousClock.now + .seconds(2)
        while backend.sessions.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(backend.createdLocales == ["en-US"])

        let liveExtra: [Float] = (totalSamples..<(totalSamples + 3_200)).map { 0.2 + Float($0) * 1e-6 }
        capture.emit(samples: liveExtra, level: 0.6)
        engine.stop()

        let final = try #require(await nextFinalResult(&results))
        #expect(final.text == "hello from auto route")
        let fed = backend.sessions[0].fedSamples
        #expect(fed.count == totalSamples + 3_200)
        #expect(abs(fed[0] - 0.2) < 1e-7)
        #expect(abs(fed[fed.count - 1] - (0.2 + Float(totalSamples + 3_199) * 1e-6)) < 1e-5)
        let telemetry = engine.routingTelemetry(for: "s-en")
        #expect(telemetry?.routedLanguageCode == "en-US")
        #expect(telemetry?.routingReason == .earlyLockSecondary)
        engine.teardown()
    }

    @MainActor
    @Test func shortUtteranceStopStillRoutesToEnglishAndZeroSampleStopCompletesEmpty() async throws {
        let suiteName = "EngineShortStopTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let capture = FakeCapture()
        let backend = FakeRecognitionBackend(finalTextByLocale: ["en-US": "Submit"])
        let lid = FakeLanguageIdentifier(
            scores: SpokenLanguageScores(
                logProbabilitiesByCode: ["en": log(0.95), "zh": log(0.01)],
                fbankMs: 0.1,
                inferenceMs: 3.0
            )
        )

        let engine = AppleSpeechDictationEngine(
            settingsStore: SpeechRecognitionSettingsStore(defaults: defaults),
            audioCapture: capture,
            recognitionBackend: backend,
            languageIdentifier: lid,
            routingTargetsResolver: { _ in
                SpeechRecognitionSettingsStore.PreparedRoutingTargets(
                    primary: .init(
                        language: .chineseSimplified, locale: Locale(identifier: "zh-CN"), backend: .speechTranscriber),
                    secondary: .init(
                        language: .englishUS, locale: Locale(identifier: "en-US"), backend: .speechTranscriber),
                    backend: .speechTranscriber
                )
            }
        )

        var results = engine.resultStream.makeAsyncIterator()

        // Case A: Zero-sample immediate stop completes empty without creating SpeechAnalyzer.
        try await engine.start(sessionId: "s-empty")
        engine.stop()
        let emptyFinal = try #require(await nextFinalResult(&results))
        #expect(emptyFinal.sessionId == "s-empty")
        #expect(emptyFinal.text.isEmpty)
        #expect(backend.createdLocales.isEmpty)

        // Case B: 0.6s short English utterance stopped before 1.5s still routes to en-US.
        try await engine.start(sessionId: "s-submit")
        let shortAudio = [Float](repeating: 0.25, count: 9_600)  // 0.6s active speech
        capture.emit(samples: shortAudio, level: 0.7)
        engine.stop()

        let submitFinal = try #require(await nextFinalResult(&results))
        #expect(submitFinal.sessionId == "s-submit")
        #expect(submitFinal.text == "Submit")
        #expect(backend.createdLocales == ["en-US"])
        #expect(engine.routingTelemetry(for: "s-submit")?.routingReason == .finalSecondary)
        engine.teardown()
    }

    @MainActor
    @Test func cancelDuringActiveSessionEmitsNoFinalAndSerializesAnalyzerHandoffToSessionB() async throws {
        let suiteName = "EngineCancelHandoffTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let capture = FakeCapture()
        let backend = FakeRecognitionBackend(
            finalTextByLocale: ["zh-CN": "session B text"],
            suspendFirstCancel: true
        )
        let lid = FakeLanguageIdentifier(
            scores: SpokenLanguageScores(
                logProbabilitiesByCode: ["zh": log(0.99), "en": log(0.001)], fbankMs: 0.1, inferenceMs: 1.0))

        let engine = AppleSpeechDictationEngine(
            settingsStore: SpeechRecognitionSettingsStore(defaults: defaults),
            audioCapture: capture,
            recognitionBackend: backend,
            languageIdentifier: lid,
            routingTargetsResolver: { _ in
                SpeechRecognitionSettingsStore.PreparedRoutingTargets(
                    primary: .init(
                        language: .chineseSimplified, locale: Locale(identifier: "zh-CN"), backend: .speechTranscriber),
                    secondary: nil,
                    backend: .speechTranscriber
                )
            }
        )

        var results = engine.resultStream.makeAsyncIterator()

        // Start Session A and push audio so Session A creates its analyzer.
        try await engine.start(sessionId: "session-A")
        capture.emit(samples: [Float](repeating: 0.2, count: 1_600), level: 0.5)
        let waitA = ContinuousClock.now + .seconds(2)
        while backend.sessions.isEmpty, ContinuousClock.now < waitA {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(backend.sessions.count == 1)
        let sessionA = backend.sessions[0]

        // Cancel Session A (its cancelAndFinishNow is suspended!) and immediately start Session B.
        engine.cancel()
        try await engine.start(sessionId: "session-B")
        capture.emit(samples: [Float](repeating: 0.3, count: 3_200), level: 0.5)

        // Session B must NOT create/start its analyzer while Session A's cancelAndFinishNow is in flight.
        try await Task.sleep(for: .milliseconds(40))
        #expect(backend.sessions.count == 1)

        // Release Session A's teardown -> Session B now starts its analyzer and finishes cleanly.
        sessionA.resumeCancel()
        engine.stop()

        let final = try #require(await nextFinalResult(&results))
        #expect(final.sessionId == "session-B")
        #expect(final.text == "session B text")
        #expect(backend.sessions.count == 2)
        #expect(backend.sessions[1].fedSamples.count == 3_200)
        engine.teardown()
    }

    @MainActor
    @Test func firstFrameWatchdogFailsCleanlyWhenNoAudioArrives() async throws {
        let suiteName = "EngineWatchdogTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let capture = FakeCapture()
        let backend = FakeRecognitionBackend(finalTextByLocale: [:])
        let engine = AppleSpeechDictationEngine(
            settingsStore: SpeechRecognitionSettingsStore(defaults: defaults),
            audioCapture: capture,
            recognitionBackend: backend,
            configuration: .init(
                routingPolicy: .default,
                maxUnconsumedSamples: 16_000,
                firstFrameTimeout: .milliseconds(60),
                lidStopBudget: .milliseconds(100),
                analyzerStartTimeout: .seconds(1),
                volumeThrottleInterval: .milliseconds(20)
            ),
            routingTargetsResolver: { _ in
                SpeechRecognitionSettingsStore.PreparedRoutingTargets(
                    primary: .init(
                        language: .chineseSimplified, locale: Locale(identifier: "zh-CN"), backend: .speechTranscriber),
                    secondary: nil,
                    backend: .speechTranscriber
                )
            }
        )

        var failures = engine.failureStream.makeAsyncIterator()
        try await engine.start(sessionId: "s-silent-mic")
        let failure = await failures.next()
        #expect(failure?.sessionId == "s-silent-mic")
        #expect(backend.sessions.isEmpty)
        engine.teardown()
    }

    // MARK: - 6. Atomic Keyboard Stale-Timeout Transaction

    @Test func staleSessionResolutionDoesNotClobberFreshOrAlreadyReadySession() {
        let manager = SharedDictationManager()
        let sessionId = "kb-race-\(UUID().uuidString)"

        #expect(manager.beginKeyboardSession(sessionId: sessionId))
        manager.heartbeat()
        #expect(manager.transitionState(for: sessionId, from: [.requestStart], to: .transcribing))

        // 1. Fresh heartbeat & updatedAt -> must stay fresh.
        let fresh = manager.resolveStaleSessionIfNeeded(
            for: sessionId,
            expectedStates: [.requestStop, .transcribing],
            requireAppDead: false
        )
        if case .stillFresh = fresh {
            // Expected
        } else {
            Issue.record("Expected .stillFresh for active transcribing session")
        }

        // 2. Main app commits `.ready` concurrently -> timeout check must return `.alreadyReady` and NOT cancel.
        #expect(manager.completeSession(for: sessionId, from: [.transcribing], finalText: "saved transcript"))
        let readyRes = manager.resolveStaleSessionIfNeeded(
            for: sessionId,
            expectedStates: [.requestStop, .transcribing],
            requireAppDead: false,
            now: Date().addingTimeInterval(30)
        )
        if case .alreadyReady(let readySession) = readyRes {
            #expect(readySession.finalText == "saved transcript")
            #expect(manager.getSession()?.state == .ready)
        } else {
            Issue.record("Expected .alreadyReady so keyboard still inserts transcript")
        }

        // 3. New genuinely stale session -> transitions atomically to `.cancelled`.
        let staleId = "kb-stale-\(UUID().uuidString)"
        #expect(manager.transitionState(for: sessionId, from: [.ready], to: .inserted))
        #expect(manager.beginKeyboardSession(sessionId: staleId))
        #expect(manager.transitionState(for: staleId, from: [.requestStart], to: .transcribing))
        let cancelledRes = manager.resolveStaleSessionIfNeeded(
            for: staleId,
            expectedStates: [.requestStop, .transcribing],
            requireAppDead: false,
            now: Date().addingTimeInterval(30)
        )
        if case .cancelled = cancelledRes {
            #expect(manager.getSession()?.state == .cancelled)
        } else {
            Issue.record("Expected .cancelled for genuinely stale session")
        }
        manager.clearPendingKeyboardSessionId(ifMatching: sessionId)
        manager.clearPendingKeyboardSessionId(ifMatching: staleId)
    }

    // MARK: - Helpers

    private func nextFinalResult(
        _ iterator: inout AsyncStream<ASRResult>.AsyncIterator
    ) async -> ASRResult? {
        while let result = await iterator.next() {
            if result.isFinal { return result }
        }
        return nil
    }
}

// MARK: - Test Doubles

private final class FakeCapture: ASRAudioCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ASRAudioFrameHandler?
    private(set) var stopCount = 0

    func prepare() async throws {}

    func start(handler: @escaping ASRAudioFrameHandler) async throws {
        lock.withLock { self.handler = handler }
    }

    func stop() {
        lock.withLock {
            stopCount += 1
            handler = nil
        }
    }

    func reset() async throws {}
    func teardown() { stop() }

    func emit(samples: [Float], level: Float) {
        let current = lock.withLock { handler }
        current?(.success(ASRAudioFrame(samples: samples, level: level)))
    }
}

private final class FakeLanguageIdentifier: SpokenLanguageIdentifying, @unchecked Sendable {
    private let lock = NSLock()
    private let scores: SpokenLanguageScores
    private(set) var identifyCallCount = 0
    var isModelAvailable: Bool = true

    init(scores: SpokenLanguageScores) {
        self.scores = scores
    }

    func preload() async {}
    func unload() {}

    func identify(samples _: [Float]) async throws -> SpokenLanguageScores {
        lock.withLock { identifyCallCount += 1 }
        return scores
    }
}

private final class FakeRecognitionBackend: AppleSpeechRecognitionBackend, @unchecked Sendable {
    private let lock = NSLock()
    private let finalTextByLocale: [String: String]
    private let suspendFirstCancel: Bool
    private(set) var createdLocales: [String] = []
    private(set) var sessions: [FakeRecognitionSession] = []

    init(finalTextByLocale: [String: String], suspendFirstCancel: Bool = false) {
        self.finalTextByLocale = finalTextByLocale
        self.suspendFirstCancel = suspendFirstCancel
    }

    func makeSession(locale: Locale, backend _: SpeechTranscriberBackend) -> any AppleSpeechRecognitionSession {
        lock.withLock {
            let isFirst = sessions.isEmpty
            let id = locale.identifier
            createdLocales.append(id)
            let session = FakeRecognitionSession(
                finalText: finalTextByLocale[id] ?? "",
                suspendCancel: suspendFirstCancel && isFirst
            )
            sessions.append(session)
            return session
        }
    }
}

private final class FakeRecognitionSession: AppleSpeechRecognitionSession, @unchecked Sendable {
    let updates: AsyncThrowingStream<AppleSpeechPartialUpdate, any Error>

    private let continuation: AsyncThrowingStream<AppleSpeechPartialUpdate, any Error>.Continuation
    private let finalText: String
    private let suspendCancel: Bool
    private let lock = NSLock()
    private var samples: [Float] = []
    private var cancelContinuation: CheckedContinuation<Void, Never>?

    var fedSamples: [Float] { lock.withLock { samples } }

    init(finalText: String, suspendCancel: Bool) {
        self.finalText = finalText
        self.suspendCancel = suspendCancel
        (updates, continuation) = AsyncThrowingStream.makeStream()
    }

    func start(hotwords _: [String]) async throws {}

    func feed(samples newSamples: [Float]) throws {
        lock.withLock { samples.append(contentsOf: newSamples) }
    }

    func finalizeAndFinish() async throws {
        if !finalText.isEmpty {
            continuation.yield(AppleSpeechPartialUpdate(text: finalText, isFinal: true))
        }
        continuation.finish()
    }

    func cancelAndFinishNow() async {
        continuation.finish()
        if suspendCancel {
            await withCheckedContinuation { cont in
                lock.withLock { cancelContinuation = cont }
            }
        }
    }

    func resumeCancel() {
        let cont: CheckedContinuation<Void, Never>? = lock.withLock {
            let c = cancelContinuation
            cancelContinuation = nil
            return c
        }
        cont?.resume()
    }
}
