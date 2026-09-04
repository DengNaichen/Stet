import Foundation
import Testing
@testable import StetMobile

@MainActor
struct FunASRRealtimeEngineTests {
    @Test func waitsForTaskStartedStreamsPartialsAndFinalizesOnlyAtTaskFinished() async throws {
        let transport = TestFunASRTransport()
        let capture = TestFunASRAudioCapture()
        let backgroundActivity = TestFunASRStartupBackgroundActivityManager()
        let configuration = try FunASRConfiguration(
            region: .beijing,
            workspaceID: "workspace-123",
            apiKey: "api-key"
        )
        let engine = FunASRRealtimeEngine(
            configurationProvider: { configuration },
            audioCapture: capture,
            transportFactory: { transport },
            startupBackgroundActivity: backgroundActivity
        )
        var textSends = transport.textSends.makeAsyncIterator()
        var dataSends = transport.dataSends.makeAsyncIterator()
        var results = engine.resultStream.makeAsyncIterator()

        try await engine.prepare()
        let startTask = Task { @MainActor in
            try await engine.start(sessionId: "session-a")
        }

        let runTask = try #require(await textSends.next())
        #expect(try action(in: runTask) == "run-task")
        #expect(backgroundActivity.beginCallCount == 1)
        #expect(backgroundActivity.endCallCount == 0)
        #expect(capture.startCount == 0)
        #expect(await transport.sentAudioCount == 0)

        await transport.emit(text: #"{"header":{"event":"task-started"}}"#)
        try await startTask.value
        #expect(backgroundActivity.endCallCount == 1)
        #expect(capture.startCount == 1)

        let audioSamples = Array(repeating: Float(0.25), count: 1_600)
        let encodedAudioFrame = FunASRPCM16Encoder.encode(samples: audioSamples)
        capture.emit(samples: audioSamples)
        #expect(await dataSends.next() == encodedAudioFrame)

        await transport.emit(
            text:
                #"{"header":{"event":"result-generated"},"payload":{"output":{"sentence":{"sentence_id":1,"text":"hello","sentence_end":false}}}}"#
        )
        let firstPartial = try #require(await results.next())
        #expect(firstPartial.text == "hello")
        #expect(!firstPartial.isFinal)

        await transport.emit(
            text:
                #"{"header":{"event":"result-generated"},"payload":{"output":{"sentence":{"sentence_id":1,"text":"hello world","sentence_end":true}}}}"#
        )
        let sentenceEnd = try #require(await results.next())
        #expect(sentenceEnd.text == "hello world")
        #expect(!sentenceEnd.isFinal)

        engine.stop()
        let finishTask = try #require(await textSends.next())
        #expect(try action(in: finishTask) == "finish-task")
        #expect(try taskID(in: finishTask) == taskID(in: runTask))

        await transport.emit(text: #"{"header":{"event":"task-finished"}}"#)
        let final = try #require(await results.next())
        #expect(final.sessionId == "session-a")
        #expect(final.text == "hello world")
        #expect(final.isFinal)

        #expect(capture.isPrepared)
        let secondStartTask = Task { @MainActor in
            try await engine.start(sessionId: "session-b")
        }
        _ = try #require(await textSends.next())
        await transport.emit(text: #"{"header":{"event":"task-started"}}"#)
        try await secondStartTask.value
        #expect(capture.prepareCount == 1)
        #expect(capture.startCount == 2)
        #expect(backgroundActivity.endCallCount == 2)

        engine.teardown()
        #expect(!capture.isPrepared)
    }

    @Test func cancellingStartupClosesHandshakeAndEndsBackgroundActivity() async throws {
        let transport = TestFunASRTransport()
        let capture = TestFunASRAudioCapture()
        let backgroundActivity = TestFunASRStartupBackgroundActivityManager()
        let configuration = try FunASRConfiguration(
            region: .beijing,
            workspaceID: "workspace-123",
            apiKey: "api-key"
        )
        let engine = FunASRRealtimeEngine(
            configurationProvider: { configuration },
            audioCapture: capture,
            transportFactory: { transport },
            startupBackgroundActivity: backgroundActivity
        )
        var textSends = transport.textSends.makeAsyncIterator()

        let startTask = Task { @MainActor in
            try await engine.start(sessionId: "session-cancelled")
        }
        _ = try #require(await textSends.next())

        startTask.cancel()
        do {
            try await startTask.value
            Issue.record("Cancelled FunASR startup unexpectedly succeeded")
        } catch is CancellationError {
            // Expected: cancellation closes the pending WebSocket receive.
        }

        #expect(backgroundActivity.beginCallCount == 1)
        #expect(backgroundActivity.endCallCount == 1)
        #expect(capture.startCount == 0)
        #expect(await transport.closeCallCount > 0)
        engine.teardown()
    }

    private func action(in text: String) throws -> String {
        let header = try header(in: text)
        return try #require(header["action"] as? String)
    }

    private func taskID(in text: String) throws -> String {
        let header = try header(in: text)
        return try #require(header["task_id"] as? String)
    }

    private func header(in text: String) throws -> [String: Any] {
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        return try #require(object["header"] as? [String: Any])
    }
}

@MainActor
private final class TestFunASRStartupBackgroundActivityManager:
    FunASRStartupBackgroundActivityManaging
{
    private(set) var beginCallCount = 0
    private(set) var endCallCount = 0

    func begin(expirationHandler _: @escaping @MainActor @Sendable () -> Void) {
        beginCallCount += 1
    }

    func end() {
        endCallCount += 1
    }
}

private final class TestFunASRAudioCapture: ASRAudioCapturing, @unchecked Sendable {
    private var handler: ASRAudioFrameHandler?
    private(set) var prepareCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var isPrepared = false

    func prepare() async throws {
        prepareCount += 1
        isPrepared = true
    }

    func start(
        handler: @escaping ASRAudioFrameHandler
    ) async throws {
        guard isPrepared else { throw FunASRError.audioUnavailable }
        startCount += 1
        self.handler = handler
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    func reset() async throws {}

    func teardown() {
        handler = nil
        isPrepared = false
    }

    func emit(samples: [Float]) {
        handler?(.success(ASRAudioFrame(samples: samples, level: 0.5)))
    }
}

private actor TestFunASRTransport: FunASRWebSocketTransport {
    nonisolated let textSends: AsyncStream<String>
    nonisolated let dataSends: AsyncStream<Data>

    private let textSendContinuation: AsyncStream<String>.Continuation
    private let dataSendContinuation: AsyncStream<Data>.Continuation
    private var queuedMessages: [FunASRWebSocketMessage] = []
    private var receivers: [CheckedContinuation<FunASRWebSocketMessage, Error>] = []
    private(set) var sentAudioCount = 0
    private(set) var closeCallCount = 0

    init() {
        (textSends, textSendContinuation) = AsyncStream.makeStream()
        (dataSends, dataSendContinuation) = AsyncStream.makeStream()
    }

    func connect(request _: URLRequest) async throws {}

    func send(text: String) async throws {
        textSendContinuation.yield(text)
    }

    func send(data: Data) async throws {
        sentAudioCount += 1
        dataSendContinuation.yield(data)
    }

    func receive() async throws -> FunASRWebSocketMessage {
        if !queuedMessages.isEmpty {
            return queuedMessages.removeFirst()
        }
        return try await withCheckedThrowingContinuation { continuation in
            receivers.append(continuation)
        }
    }

    func close() async {
        closeCallCount += 1
        let receivers = self.receivers
        self.receivers.removeAll()
        queuedMessages.removeAll()
        for receiver in receivers {
            receiver.resume(throwing: FunASRError.connectionFailed)
        }
    }

    func emit(text: String) {
        let message = FunASRWebSocketMessage.text(text)
        if receivers.isEmpty {
            queuedMessages.append(message)
        } else {
            receivers.removeFirst().resume(returning: message)
        }
    }
}
