import AVFoundation
import Foundation
import Testing
@testable import StetMobile

struct ASRAudioCaptureTests {
    @Test func builtInStrategyNeverAdvertisesBluetoothInput() {
        let options = ASRAudioInputStrategy.builtInPreferred.categoryOptions

        #expect(options.contains(.mixWithOthers))
        #expect(!options.contains(.allowBluetoothHFP))
        if #available(iOS 26.0, *) {
            #expect(!options.contains(.bluetoothHighQualityRecording))
        }
    }

    @Test func airPodsStrategyRetainsHFPAndHighQualityRecording() {
        let options = ASRAudioInputStrategy.airPodsHighQuality.categoryOptions

        #expect(options.contains(.mixWithOthers))
        #expect(options.contains(.allowBluetoothHFP))
        if #available(iOS 26.0, *) {
            #expect(options.contains(.bluetoothHighQualityRecording))
        }
    }

    @Test func routeResolutionDistinguishesPreferredInputFromSystemFallback() {
        let builtInType = AVAudioSession.Port.builtInMic.rawValue

        #expect(
            ASRAudioInputStrategy.builtInPreferred.resolve(
                actualInputPortTypes: [builtInType]
            ) == .preferredInputActive
        )
        #expect(
            ASRAudioInputStrategy.builtInPreferred.resolve(
                actualInputPortTypes: [AVAudioSession.Port.bluetoothHFP.rawValue]
            )
                == .systemFallback(
                    actualInputPortTypes: [AVAudioSession.Port.bluetoothHFP.rawValue]
                )
        )
    }

    @Test func prepareKeepsHardwareWarmWhileStartAndStopOnlyGateFrames() async throws {
        let hardware = TestASRAudioCaptureHardware()
        let capture = PersistentASRAudioCapture(
            strategy: .builtInPreferred,
            hardware: hardware
        )
        let receivedFrames = LockedFrameCounter()

        try await capture.prepare()
        hardware.emit(.success(ASRAudioFrame(samples: [0.1], level: 0.2)))
        #expect(hardware.prepareCount == 1)
        #expect(hardware.isRunning)
        #expect(receivedFrames.count == 0)

        try await capture.start { result in
            if case .success = result {
                receivedFrames.increment()
            }
        }
        hardware.emit(.success(ASRAudioFrame(samples: [0.2], level: 0.3)))
        #expect(receivedFrames.count == 1)

        do {
            try await capture.start { _ in }
            Issue.record("Expected a second active consumer to be rejected")
        } catch let error as ASRAudioCaptureError {
            #expect(error == .consumerAlreadyActive)
        }

        capture.stop()
        hardware.emit(.success(ASRAudioFrame(samples: [0.3], level: 0.4)))
        #expect(hardware.isRunning)
        #expect(receivedFrames.count == 1)

        capture.teardown()
        #expect(!hardware.isRunning)
        #expect(hardware.teardownCount == 1)
    }

    @Test func systemFallbackStillDeliversFrames() async throws {
        let fallback = ASRAudioRouteResolution.systemFallback(
            actualInputPortTypes: [AVAudioSession.Port.bluetoothHFP.rawValue]
        )
        let hardware = TestASRAudioCaptureHardware(routeResolution: fallback)
        let capture = PersistentASRAudioCapture(
            strategy: .builtInPreferred,
            hardware: hardware
        )
        let receivedFrames = LockedFrameCounter()

        try await capture.prepare()
        try await capture.start { result in
            if case .success = result {
                receivedFrames.increment()
            }
        }
        hardware.emit(.success(ASRAudioFrame(samples: [0.2], level: 0.3)))

        #expect(hardware.prepareResolution == fallback)
        #expect(receivedFrames.count == 1)
        capture.teardown()
    }

    @Test func resetRebuildsHardwareWithoutDroppingTheActiveConsumer() async throws {
        let hardware = TestASRAudioCaptureHardware()
        let capture = PersistentASRAudioCapture(
            strategy: .builtInPreferred,
            hardware: hardware
        )
        let receivedFrames = LockedFrameCounter()

        try await capture.prepare()
        try await capture.start { result in
            if case .success = result {
                receivedFrames.increment()
            }
        }
        hardware.emit(.success(ASRAudioFrame(samples: [0.1], level: 0.2)))

        try await capture.reset()
        hardware.emit(.success(ASRAudioFrame(samples: [0.2], level: 0.3)))

        #expect(hardware.rebuildCount == 1)
        #expect(receivedFrames.count == 2)
        capture.teardown()
    }

    @Test func routeRecoveryCoalescesRepeatedNotificationsAndPreservesHandler() async throws {
        let hardware = TestASRAudioCaptureHardware(suspendsRebuilds: true)
        let capture = PersistentASRAudioCapture(
            strategy: .builtInPreferred,
            hardware: hardware
        )
        let receivedFrames = LockedFrameCounter()
        var rebuildStarts = hardware.rebuildStarts.makeAsyncIterator()
        var rebuildFinishes = hardware.rebuildFinishes.makeAsyncIterator()

        try await capture.prepare()
        try await capture.start { result in
            if case .success = result {
                receivedFrames.increment()
            }
        }

        capture.receiveRouteChange(reason: .oldDeviceUnavailable)
        _ = try #require(await rebuildStarts.next())
        capture.receiveRouteChange(reason: .newDeviceAvailable)
        capture.receiveRouteChange(reason: .newDeviceAvailable)
        hardware.resumeNextRebuild()
        _ = try #require(await rebuildFinishes.next())

        _ = try #require(await rebuildStarts.next())
        #expect(hardware.rebuildCount == 2)
        hardware.resumeNextRebuild()
        _ = try #require(await rebuildFinishes.next())

        hardware.emit(.success(ASRAudioFrame(samples: [0.4], level: 0.5)))
        #expect(receivedFrames.count == 1)

        capture.receiveRouteChange(reason: .routeConfigurationChange)
        #expect(hardware.rebuildCount == 2)
        capture.teardown()
    }
}

nonisolated private final class LockedFrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock { value }
    }

    func increment() {
        lock.withLock { value += 1 }
    }
}

nonisolated private final class TestASRAudioCaptureHardware:
    ASRAudioCaptureHardware, @unchecked Sendable
{
    private struct State {
        var isRunning = false
        var prepareCount = 0
        var rebuildCount = 0
        var teardownCount = 0
        var handler: ASRAudioFrameHandler?
        var rebuildContinuations: [CheckedContinuation<Void, Never>] = []
    }

    let rebuildStarts: AsyncStream<Void>
    let rebuildFinishes: AsyncStream<Void>

    private let rebuildStartContinuation: AsyncStream<Void>.Continuation
    private let rebuildFinishContinuation: AsyncStream<Void>.Continuation
    private let suspendsRebuilds: Bool
    private let routeResolution: ASRAudioRouteResolution
    private let lock = NSLock()
    private var state = State()

    init(
        suspendsRebuilds: Bool = false,
        routeResolution: ASRAudioRouteResolution = .preferredInputActive
    ) {
        self.suspendsRebuilds = suspendsRebuilds
        self.routeResolution = routeResolution
        (rebuildStarts, rebuildStartContinuation) = AsyncStream.makeStream()
        (rebuildFinishes, rebuildFinishContinuation) = AsyncStream.makeStream()
    }

    var prepareResolution: ASRAudioRouteResolution {
        routeResolution
    }

    var isRunning: Bool {
        lock.withLock { state.isRunning }
    }

    var prepareCount: Int {
        lock.withLock { state.prepareCount }
    }

    var rebuildCount: Int {
        lock.withLock { state.rebuildCount }
    }

    var teardownCount: Int {
        lock.withLock { state.teardownCount }
    }

    func prepare(frameHandler: @escaping ASRAudioFrameHandler) async throws
        -> ASRAudioRouteResolution
    {
        lock.withLock {
            state.prepareCount += 1
            state.isRunning = true
            state.handler = frameHandler
        }
        return routeResolution
    }

    func rebuild(frameHandler: @escaping ASRAudioFrameHandler) async throws
        -> ASRAudioRouteResolution
    {
        lock.withLock {
            state.rebuildCount += 1
            state.isRunning = true
            state.handler = frameHandler
        }
        if suspendsRebuilds {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    state.rebuildContinuations.append(continuation)
                }
                rebuildStartContinuation.yield()
            }
        } else {
            rebuildStartContinuation.yield()
        }
        rebuildFinishContinuation.yield()
        return routeResolution
    }

    func teardown() {
        let continuations = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            state.teardownCount += 1
            state.isRunning = false
            state.handler = nil
            defer { state.rebuildContinuations.removeAll() }
            return state.rebuildContinuations
        }
        for continuation in continuations {
            continuation.resume()
        }
        rebuildStartContinuation.finish()
        rebuildFinishContinuation.finish()
    }

    func emit(_ result: Result<ASRAudioFrame, ASRAudioCaptureError>) {
        let handler = lock.withLock { state.handler }
        handler?(result)
    }

    func resumeNextRebuild() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            guard !state.rebuildContinuations.isEmpty else { return nil }
            return state.rebuildContinuations.removeFirst()
        }
        continuation?.resume()
    }
}
