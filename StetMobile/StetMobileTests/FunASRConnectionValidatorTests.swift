import Foundation
import Testing
@testable import StetMobile

@MainActor
struct FunASRConnectionValidatorTests {
    @Test func succeedsAtTaskStartedWithoutSendingAudioOrFinishTask() async throws {
        let transport = ValidationTransport()
        let validator = FunASRConnectionValidator(transportFactory: { transport })
        let configuration = try FunASRConfiguration(
            region: .beijing,
            workspaceID: "workspace-123",
            apiKey: "api-key"
        )
        var textSends = transport.textSends.makeAsyncIterator()

        let validation = Task { @MainActor in
            try await validator.validate(configuration: configuration)
        }

        let runTask = try #require(await textSends.next())
        #expect(try action(in: runTask) == "run-task")

        await transport.emit(text: #"{"header":{"event":"task-started"}}"#)
        try await validation.value

        #expect(await textSends.next() == nil)
        #expect(await transport.audioSendCount == 0)
        #expect(await transport.closeCount == 1)
    }

    private func action(in text: String) throws -> String {
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        let header = try #require(object["header"] as? [String: Any])
        return try #require(header["action"] as? String)
    }
}

private actor ValidationTransport: FunASRWebSocketTransport {
    nonisolated let textSends: AsyncStream<String>

    private let textContinuation: AsyncStream<String>.Continuation
    private var queuedMessages: [FunASRWebSocketMessage] = []
    private var receivers: [CheckedContinuation<FunASRWebSocketMessage, Error>] = []
    private(set) var audioSendCount = 0
    private(set) var closeCount = 0

    init() {
        (textSends, textContinuation) = AsyncStream.makeStream()
    }

    func connect(request _: URLRequest) async throws {}

    func send(text: String) async throws {
        textContinuation.yield(text)
    }

    func send(data _: Data) async throws {
        audioSendCount += 1
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
        closeCount += 1
        textContinuation.finish()
        let receivers = self.receivers
        self.receivers.removeAll()
        queuedMessages.removeAll()
        for receiver in receivers {
            receiver.resume(throwing: CancellationError())
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
