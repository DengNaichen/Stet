import Foundation
import MCP
@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1
@preconcurrency import NIOPosix

actor StetMCPHTTPServer {
    struct Configuration: Sendable, Equatable {
        let host: String
        let port: Int
        let endpoint: String

        static let `default` = Configuration(
            host: "127.0.0.1",
            port: 49_321,
            endpoint: "/mcp"
        )
    }

    typealias RequestHandler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let configuration: Configuration
    private let requestHandler: RequestHandler
    private var channel: Channel?
    private var connections: MCPHTTPConnections?
    private var runID: UUID?
    private var isStopping = false

    init(
        configuration: Configuration = .default,
        requestHandler: @escaping RequestHandler
    ) {
        self.configuration = configuration
        self.requestHandler = requestHandler
    }

    func run(onReady: @Sendable () async -> Void = {}) async throws {
        guard runID == nil else { return }
        let id = UUID()
        runID = id
        isStopping = false
        let connections = MCPHTTPConnections()
        self.connections = connections
        defer {
            if runID == id {
                runID = nil
                channel = nil
                self.connections = nil
            }
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: max(1, min(2, System.coreCount)))
        let endpoint = configuration.endpoint
        let requestHandler = self.requestHandler
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 16)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                connections.insert(channel)
                return channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(
                        StetMCPNIOHTTPHandler(endpoint: endpoint, requestHandler: requestHandler)
                    )
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

        let boundChannel: Channel
        do {
            boundChannel = try await bootstrap.bind(
                host: configuration.host,
                port: configuration.port
            ).get()
        } catch {
            await connections.closeAll()
            try? await group.shutdownGracefully()
            throw error
        }
        guard runID == id, !isStopping, !Task.isCancelled else {
            try? await boundChannel.close().get()
            await connections.closeAll()
            try? await group.shutdownGracefully()
            throw CancellationError()
        }

        channel = boundChannel
        await onReady()

        do {
            try await withTaskCancellationHandler {
                try await boundChannel.closeFuture.get()
            } onCancel: {
                Task { await self.stop(runID: id) }
            }
        } catch {
            channel = nil
            await connections.closeAll()
            try? await group.shutdownGracefully()
            throw error
        }

        channel = nil
        await connections.closeAll()
        try await group.shutdownGracefully()
    }

    private func stop(runID: UUID) async {
        guard self.runID == runID else { return }
        await stop()
    }

    func stop() async {
        isStopping = true
        let connections = self.connections
        if let channel { try? await channel.close().get() }
        await connections?.closeAll()
    }

    func listeningPort() -> Int? { channel?.localAddress?.port }

    func isListening() -> Bool {
        channel != nil
    }
}

private nonisolated final class StetMCPNIOHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private struct RequestState {
        var head: HTTPRequestHead
        var bodyBuffer: ByteBuffer
    }

    private let endpoint: String
    private let requestHandler: StetMCPHTTPServer.RequestHandler
    private var requestState: RequestState?
    private var requestTasks: [UUID: Task<Void, Never>] = [:]

    init(
        endpoint: String,
        requestHandler: @escaping StetMCPHTTPServer.RequestHandler
    ) {
        self.endpoint = endpoint
        self.requestHandler = requestHandler
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestState = RequestState(
                head: head,
                bodyBuffer: context.channel.allocator.buffer(capacity: 0)
            )
        case .body(var buffer):
            requestState?.bodyBuffer.writeBuffer(&buffer)
        case .end:
            guard let state = requestState else { return }
            requestState = nil

            let path = state.head.uri.split(separator: "?").first.map(String.init) ?? state.head.uri
            guard path == endpoint else {
                writeResponse(
                    .error(statusCode: 404, .invalidRequest("Not Found")),
                    version: state.head.version, context: context
                )
                return
            }
            let request = makeHTTPRequest(from: state, path: path)
            let id = UUID()
            nonisolated(unsafe) let context = context
            requestTasks[id] = Task { [requestHandler] in
                let response = await requestHandler(request)
                guard !Task.isCancelled else { return }
                context.eventLoop.execute {
                    guard self.requestTasks.removeValue(forKey: id) != nil, context.channel.isActive else { return }
                    self.writeResponse(response, version: state.head.version, context: context)
                }
            }
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        for task in requestTasks.values { task.cancel() }
        requestTasks.removeAll()
        requestState = nil
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    private func makeHTTPRequest(from state: RequestState, path: String) -> HTTPRequest {
        var headers: [String: String] = [:]
        for (name, value) in state.head.headers {
            if let existing = headers[name] {
                headers[name] = existing + ", " + value
            } else {
                headers[name] = value
            }
        }

        let body: Data?
        if state.bodyBuffer.readableBytes > 0,
            let bytes = state.bodyBuffer.getBytes(
                at: 0,
                length: state.bodyBuffer.readableBytes
            )
        {
            body = Data(bytes)
        } else {
            body = nil
        }

        return HTTPRequest(
            method: state.head.method.rawValue,
            headers: headers,
            body: body,
            path: path
        )
    }

    private func writeResponse(
        _ response: HTTPResponse,
        version: HTTPVersion,
        context: ChannelHandlerContext
    ) {
        context.eventLoop.preconditionInEventLoop()
        let body = response.bodyData

        var head = HTTPResponseHead(
            version: version,
            status: HTTPResponseStatus(statusCode: response.statusCode)
        )
        for (name, value) in response.headers {
            head.headers.add(name: name, value: value)
        }
        if let body {
            head.headers.replaceOrAdd(name: "Content-Length", value: String(body.count))
        } else {
            head.headers.replaceOrAdd(name: "Content-Length", value: "0")
        }

        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        if let body {
            var buffer = context.channel.allocator.buffer(capacity: body.count)
            buffer.writeBytes(body)
            context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }
}

// Membership is shared by NIO event loops and the server actor, never by the main actor.
private nonisolated final class MCPHTTPConnections: @unchecked Sendable {
    private let lock = NSLock()
    private var channels: [ObjectIdentifier: Channel] = [:]
    private var stopped = false

    func insert(_ channel: Channel) {
        let accepted = lock.withLock {
            guard !stopped else { return false }
            channels[ObjectIdentifier(channel)] = channel
            return true
        }
        guard accepted else {
            channel.close(promise: nil)
            return
        }
        channel.closeFuture.whenComplete { [weak self] _ in
            _ = self?.lock.withLock { self?.channels.removeValue(forKey: ObjectIdentifier(channel)) }
        }
    }

    func closeAll() async {
        let pending = lock.withLock {
            stopped = true
            let pending = Array(channels.values)
            channels.removeAll()
            return pending
        }
        for channel in pending { try? await channel.close().get() }
    }
}
