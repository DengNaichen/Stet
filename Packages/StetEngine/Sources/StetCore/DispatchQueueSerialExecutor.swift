import Dispatch

/// Keeps blocking platform/runtime calls off Swift's cooperative thread pool while
/// preserving actor isolation and serial ordering across those calls.
public final class DispatchQueueSerialExecutor: SerialExecutor {
    private let queue: DispatchQueue

    public init(label: String, qos: DispatchQoS = .userInitiated) {
        queue = DispatchQueue(label: label, qos: qos)
    }

    public func checkIsolated() {
        dispatchPrecondition(condition: .onQueue(queue))
    }

    public func enqueue(_ job: consuming ExecutorJob) {
        let unownedJob = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        queue.async {
            unownedJob.runSynchronously(on: executor)
        }
    }
}
