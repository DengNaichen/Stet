import Dispatch
import Foundation
import Testing

@testable import StetCore

@Suite("Dispatch Queue Serial Executor")
struct DispatchQueueSerialExecutorTests {
    @Test func blockingWorkAndResumedActorJobsStayOnDedicatedQueue() async {
        let executor = DispatchQueueSerialExecutor(label: "executor-test")
        let worker = BlockingWorker(executor: executor)

        await worker.run { executor.checkIsolated() }
        await worker.runAfterSuspension { executor.checkIsolated() }
    }

    @Test func blockingRuntimeCallDoesNotOccupyCallerOrAnotherActor() async {
        let worker = BlockingWorker(executor: DispatchQueueSerialExecutor(label: "executor-blocking-test"))
        let (entered, continuation) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let operation = Task {
            await worker.run {
                continuation.yield(())
                return release.wait(timeout: .now() + 2) == .success
            }
        }
        var iterator = entered.makeAsyncIterator()
        await iterator.next()
        let otherWorker = BlockingWorker(executor: DispatchQueueSerialExecutor(label: "executor-independent-test"))
        #expect(await otherWorker.run { 42 } == 42)
        release.signal()
        #expect(await operation.value)
    }
}

private actor BlockingWorker {
    private nonisolated let executor: DispatchQueueSerialExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }

    init(executor: DispatchQueueSerialExecutor) { self.executor = executor }

    func run<Value: Sendable>(_ operation: @Sendable () -> Value) -> Value { operation() }

    func runAfterSuspension(_ operation: @Sendable () -> Void) async {
        await Task.yield()
        operation()
    }
}
