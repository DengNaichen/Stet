import Foundation

nonisolated enum FunASRWebSocketMessage: Sendable {
    case text(String)
    case data(Data)
}

nonisolated protocol FunASRWebSocketTransport: Sendable {
    func connect(request: URLRequest) async throws
    func send(text: String) async throws
    func send(data: Data) async throws
    func receive() async throws -> FunASRWebSocketMessage
    func close() async
}

actor URLSessionFunASRWebSocketTransport: FunASRWebSocketTransport {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(request: URLRequest) async throws {
        await close()
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
    }

    func send(text: String) async throws {
        guard let task else { throw FunASRError.connectionFailed }
        try await task.send(.string(text))
    }

    func send(data: Data) async throws {
        guard let task else { throw FunASRError.connectionFailed }
        try await task.send(.data(data))
    }

    func receive() async throws -> FunASRWebSocketMessage {
        guard let task else { throw FunASRError.connectionFailed }
        switch try await task.receive() {
        case .string(let text):
            return .text(text)
        case .data(let data):
            return .data(data)
        @unknown default:
            throw FunASRError.invalidServerResponse
        }
    }

    func close() async {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}

actor FunASRWebSocketClient {
    typealias TransportFactory = @Sendable () -> any FunASRWebSocketTransport

    private let transportFactory: TransportFactory
    private var transport: (any FunASRWebSocketTransport)?
    private var connectedConfiguration: FunASRConfiguration?
    private var activeTaskID: String?

    init(
        transportFactory: @escaping TransportFactory = {
            URLSessionFunASRWebSocketTransport()
        }
    ) {
        self.transportFactory = transportFactory
    }

    func beginTask(configuration: FunASRConfiguration) async throws {
        var lastError: Error = FunASRError.connectionFailed
        for attempt in 0..<2 {
            do {
                try await ensureConnection(configuration: configuration)
                let taskID = UUID().uuidString.lowercased()
                activeTaskID = taskID
                try await sendJSON(FunASRProtocol.runTaskData(taskID: taskID))
                try await withFunASRTimeout(seconds: 10, timeoutError: .taskStartTimedOut) {
                    try await self.waitForTaskStarted()
                }
                return
            } catch is CancellationError {
                await close()
                throw CancellationError()
            } catch {
                if Task.isCancelled {
                    await close()
                    throw CancellationError()
                }
                lastError = Self.sanitized(error)
                await close()
                if attempt == 1 || lastError as? FunASRError == .authenticationFailed {
                    throw lastError
                }
            }
        }
        throw lastError
    }

    func sendAudio(_ data: Data) async throws {
        guard activeTaskID != nil, let transport else {
            throw FunASRError.connectionFailed
        }
        do {
            try await transport.send(data: data)
        } catch {
            throw Self.sanitized(error)
        }
    }

    func finishTask() async throws {
        guard let taskID = activeTaskID else { return }
        do {
            try await sendJSON(FunASRProtocol.finishTaskData(taskID: taskID))
        } catch {
            throw Self.sanitized(error)
        }
    }

    func receiveEvent() async throws -> FunASRServerEvent {
        guard let transport else { throw FunASRError.connectionFailed }
        let message: FunASRWebSocketMessage
        do {
            message = try await transport.receive()
        } catch {
            throw Self.sanitized(error)
        }

        let data: Data
        switch message {
        case .text(let text):
            guard let encoded = text.data(using: .utf8) else {
                throw FunASRError.invalidServerResponse
            }
            data = encoded
        case .data(let value):
            data = value
        }
        return try FunASRProtocol.parseServerEvent(data)
    }

    func markTaskFinished() {
        activeTaskID = nil
    }

    func close() async {
        activeTaskID = nil
        connectedConfiguration = nil
        let transport = self.transport
        self.transport = nil
        await transport?.close()
    }

    private func ensureConnection(configuration: FunASRConfiguration) async throws {
        if transport != nil, connectedConfiguration == configuration {
            return
        }

        await close()
        let transport = transportFactory()
        do {
            try await transport.connect(request: configuration.webSocketRequest)
        } catch {
            throw Self.sanitized(error)
        }
        self.transport = transport
        connectedConfiguration = configuration
    }

    private func sendJSON(_ data: Data) async throws {
        guard let transport, let text = String(data: data, encoding: .utf8) else {
            throw FunASRError.invalidServerResponse
        }
        try await transport.send(text: text)
    }

    private func waitForTaskStarted() async throws {
        while true {
            switch try await receiveEvent() {
            case .taskStarted:
                return
            case .heartbeat:
                continue
            case .taskFailed(let error):
                throw error
            case .sentence, .taskFinished:
                throw FunASRError.invalidServerResponse
            }
        }
    }

    private static func sanitized(_ error: Error) -> FunASRError {
        if let error = error as? FunASRError {
            return error
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .userAuthenticationRequired, .noPermissionsToReadFile, .badServerResponse:
                return .authenticationFailed
            default:
                return .connectionFailed
            }
        }
        return .connectionFailed
    }
}

protocol FunASRConnectionValidating {
    func validate(configuration: FunASRConfiguration) async throws
}

struct FunASRConnectionValidator: FunASRConnectionValidating {
    private let transportFactory: FunASRWebSocketClient.TransportFactory

    init(
        transportFactory: @escaping FunASRWebSocketClient.TransportFactory = {
            URLSessionFunASRWebSocketTransport()
        }
    ) {
        self.transportFactory = transportFactory
    }

    func validate(configuration: FunASRConfiguration) async throws {
        let client = FunASRWebSocketClient(transportFactory: transportFactory)
        do {
            try await client.beginTask(configuration: configuration)
            await client.close()
        } catch {
            await client.close()
            throw error
        }
    }
}

private func withFunASRTimeout<T: Sendable>(
    seconds: Int,
    timeoutError: FunASRError,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw timeoutError
        }
        guard let result = try await group.next() else {
            throw timeoutError
        }
        group.cancelAll()
        return result
    }
}
