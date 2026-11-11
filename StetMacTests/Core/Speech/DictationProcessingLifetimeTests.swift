import Foundation
import Testing

@testable import Stet

@Suite("Dictation processing resource lifetime")
struct DictationProcessingLifetimeTests {
    @Test func cleanupWaitsForProcessingAndRetiredPrewarm() async throws {
        let prewarmGate = TestSuspensionGate()
        let cleanupGate = TestSuspensionGate()
        let events = ProcessingEvents()
        let harness = ProcessingHarness {
            await events.didCleanup()
            await cleanupGate.wait()
        }
        let prewarm = Task { await prewarmGate.wait() }
        try #require(await TestSupport.eventuallyAsync { await prewarmGate.hasWaiter })
        await harness.begin(1)
        await harness.retire(prewarm)
        await harness.scheduleCleanup()
        #expect(await events.cleanups == 0)
        await harness.finish(1)
        await harness.scheduleCleanup()
        #expect(await events.cleanups == 0)
        await prewarmGate.open()
        try #require(await TestSupport.eventuallyAsync { await cleanupGate.hasWaiter })
        #expect(await events.cleanups == 1)
        let wait = Task {
            await harness.waitForCleanup()
            await events.didWait()
        }
        #expect(await events.waitFinished == false)
        await cleanupGate.open()
        await wait.value
        #expect(await events.waitFinished)
    }

    @Test func cancelledComparisonKeepsFileAndModelUntilItsWorkFinishes() async throws {
        let gate = TestSuspensionGate()
        let events = ProcessingEvents()
        let harness = ProcessingHarness { await events.didCleanup() }
        let url = TestSupport.temporaryFileURL("comparison-lifetime", ext: "wav")
        try Data("audio".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await harness.startComparison(url: url, transcriber: ComparisonTranscriber(gate: gate), events: events)
        try #require(await TestSupport.eventuallyAsync { await gate.hasWaiter })
        #expect(await harness.cancelComparison())
        await harness.scheduleCleanup()
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(await events.cleanups == 0)
        await gate.open()
        await harness.waitForComparison()
        await harness.waitForCleanup()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(await events.recordedTexts.isEmpty)
        #expect(await events.cleanups == 1)
    }

    @Test func slidingIdleTTLResetsOnNewSessionAndCleansUpAfterExpiry() async throws {
        let sleepRecorder = ControlledSleepRecorder()
        let events = ProcessingEvents()
        let harness = ProcessingHarness(
            idleTTL: .seconds(300),
            sleep: { duration in try await sleepRecorder.sleep(duration) },
            cleanup: { await events.didCleanup() }
        )

        await harness.begin(1)
        await harness.finish(1)
        await harness.scheduleCleanup()
        try #require(await TestSupport.eventuallyAsync { await sleepRecorder.activeWaiters == 1 })
        #expect(await events.cleanups == 0)

        // Starting a new capture/session cancels the pending idle TTL without unloading models.
        await harness.waitForCleanup()
        await harness.begin(2)
        #expect(await events.cleanups == 0)
        await harness.finish(2)
        await harness.scheduleCleanup()
        try #require(await TestSupport.eventuallyAsync { await sleepRecorder.totalCalls == 2 })
        #expect(await events.cleanups == 0)

        // Allowing the reset TTL to expire triggers model cleanup once.
        await sleepRecorder.completeCurrentSleep()
        try #require(await TestSupport.eventuallyAsync { await events.cleanups == 1 })
    }

    @Test func memoryPressureEvictsIdleModelsImmediatelyWithoutInterruptingActiveSession() async throws {
        let sleepRecorder = ControlledSleepRecorder()
        let events = ProcessingEvents()
        let harness = ProcessingHarness(
            idleTTL: .seconds(300),
            sleep: { duration in try await sleepRecorder.sleep(duration) },
            cleanup: { await events.didCleanup() }
        )

        // Memory pressure during active session or capture must not unload models.
        await harness.begin(1)
        await harness.evictForMemoryPressure(captureIsIdle: true)
        #expect(await events.cleanups == 0)
        await harness.finish(1)
        await harness.evictForMemoryPressure(captureIsIdle: false)
        #expect(await events.cleanups == 0)

        // Once sitting in the 300s idle TTL window, memory pressure unloads immediately.
        await harness.scheduleCleanup()
        try #require(await TestSupport.eventuallyAsync { await sleepRecorder.activeWaiters == 1 })
        #expect(await events.cleanups == 0)

        await harness.evictForMemoryPressure(captureIsIdle: true)
        try #require(await TestSupport.eventuallyAsync { await events.cleanups == 1 })
    }
}

private actor ProcessingEvents {
    private(set) var cleanups = 0
    private(set) var waitFinished = false
    private(set) var recordedTexts: [String] = []
    func didCleanup() { cleanups += 1 }
    func didWait() { waitFinished = true }
    func record(_ text: String) { recordedTexts.append(text) }
}

private actor ProcessingHarness {
    private let lifetime: DictationProcessingLifetime
    init(
        idleTTL: Duration = .zero,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        cleanup: @escaping @Sendable () async -> Void
    ) {
        lifetime = DictationProcessingLifetime(idleTTL: idleTTL, sleep: sleep, cleanupModels: cleanup)
    }
    func begin(_ id: UInt64) { lifetime.begin(id) }
    func finish(_ id: UInt64) { lifetime.finish(id) }
    func retire(_ task: Task<Void, Never>) { lifetime.retirePrewarm(task) }
    func scheduleCleanup() { lifetime.scheduleCleanupIfIdle(captureIsIdle: true, isolation: self) }
    func evictForMemoryPressure(captureIsIdle: Bool) {
        lifetime.evictIdleModelsNow(captureIsIdle: captureIsIdle, isolation: self)
    }
    func waitForCleanup() async { await lifetime.waitForCleanup(isolation: self) }
    func waitForComparison() async { await lifetime.waitForComparison(isolation: self) }
    func cancelComparison() -> Bool { lifetime.cancelComparison() }
    func startComparison(url: URL, transcriber: any AudioFileTranscriptionService, events: ProcessingEvents) {
        lifetime.startComparison(
            audioURL: url, languageCode: nil, duration: 1, transcriptionService: transcriber,
            record: { await events.record($0) }, isolation: self,
            didFinish: { self.scheduleCleanup() })
    }
}

private actor ControlledSleepRecorder {
    private var continuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    private(set) var totalCalls = 0
    var activeWaiters: Int { continuations.count }

    func sleep(_: Duration) async throws {
        try Task.checkCancellation()
        totalCalls += 1
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuations[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelSleep(id: id) }
        }
    }

    private func cancelSleep(id: UUID) {
        continuations.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    func completeCurrentSleep() {
        let all = continuations.values
        continuations.removeAll()
        for continuation in all {
            continuation.resume()
        }
    }
}

private actor ComparisonTranscriber: AudioFileTranscriptionService {
    private let gate: TestSuspensionGate
    init(gate: TestSuspensionGate) { self.gate = gate }
    func transcribe(
        audioFileAt fileURL: URL, languageCode: String?, prompt: String?, audioDurationSeconds: TimeInterval?
    )
        async throws -> TranscriptionResult
    {
        await gate.wait()
        return TranscriptionResult(text: "comparison", languageCode: languageCode)
    }
}
