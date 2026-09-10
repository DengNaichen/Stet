import Foundation
import Testing

@MainActor
@Suite("Deterministic Test Clock")
struct TestClockTests {
    @Test func advanceResumesOnlyDueSleeps() async throws {
        let clock = TestClock()
        var secondFinished = false
        let first = Task { try await clock.sleep(for: .milliseconds(100)) }
        #expect(await clock.nextSleep() == .milliseconds(100))
        let second = Task {
            try await clock.sleep(for: .milliseconds(200))
            secondFinished = true
        }
        #expect(await clock.nextSleep() == .milliseconds(200))
        await clock.advance(by: .milliseconds(100))
        try await first.value
        #expect(!secondFinished)
        await clock.advance(by: .milliseconds(100))
        try await second.value
        #expect(secondFinished)
        #expect(await clock.pendingSleepCount == 0)
    }

    @Test func cancellationRemovesPendingSleep() async {
        let clock = TestClock()
        let task = Task { try await clock.sleep(for: .seconds(1)) }
        _ = await clock.nextSleep()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await clock.pendingSleepCount == 0)
    }

    @Test func cancellationBeforeRegistrationDoesNotPark() async {
        let clock = TestClock()
        let task = Task { try await clock.sleep(for: .seconds(1)) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await clock.pendingSleepCount == 0)
    }
}
