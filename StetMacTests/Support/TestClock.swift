import Foundation

/// A clock advanced by tests, with observable sleep registration and cancellation.
actor TestClock {
    private struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var now: Duration = .zero
    private var sleepers: [UUID: Sleeper] = [:]
    private var requests: [Duration] = []
    private var observers: [CheckedContinuation<Duration, Never>] = []

    var pendingSleepCount: Int { sleepers.count }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        guard duration > .zero else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleepers[id] = Sleeper(deadline: now + duration, continuation: continuation)
                if observers.isEmpty {
                    requests.append(duration)
                } else {
                    observers.removeFirst().resume(returning: duration)
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func nextSleep() async -> Duration {
        if !requests.isEmpty { return requests.removeFirst() }
        return await withCheckedContinuation { observers.append($0) }
    }

    func advance(by duration: Duration) {
        precondition(duration >= .zero)
        now += duration
        let ready = sleepers.filter { $0.value.deadline <= now }
        for (id, sleeper) in ready {
            sleepers.removeValue(forKey: id)
            sleeper.continuation.resume()
        }
    }

    private func cancel(_ id: UUID) {
        sleepers.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }
}
