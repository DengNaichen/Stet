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
    private var eventLoopGroup: MultiThreadedEventLoopGroup?

    init(
        configuration: Configuration = .default,
        requestHandler: @escaping RequestHandler
    ) {
        self.configuration = configuration
        self.requestHandler = requestHandler
    }

    func run() async throws {
        guard channel == nil else { return }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: max(1, min(2, System.coreCount)))
        let endpoint = configuration.endpoint
        let requestHandler = self.requestHandler
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 16)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
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
            try? await group.shutdownGracefully()
            throw error
        }

        channel = boundChannel
        eventLoopGroup = group

        do {
            try await withTaskCancellationHandler {
                try await boundChannel.closeFuture.get()
            } onCancel: {
                Task { await self.stop() }
            }
        } catch {
            channel = nil
            eventLoopGroup = nil
            try? await group.shutdownGracefully()
            throw error
        }

        channel = nil
        eventLoopGroup = nil
        try await group.shutdownGracefully()
    }

    func stop() async {
        guard let channel else { return }
        try? await channel.close().get()
    }

    func isListening() -> Bool {
        channel != nil
    }
}

private final class StetMCPNIOHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private struct RequestState {
        var head: HTTPRequestHead
        var bodyBuffer: ByteBuffer
    }

    private let endpoint: String
    private let requestHandler: StetMCPHTTPServer.RequestHandler
    private var requestState: RequestState?

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

            nonisolated(unsafe) let context = context
            Task { @MainActor in
                await self.handleRequest(state: state, context: context)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    private func handleRequest(
        state: RequestState,
        context: ChannelHandlerContext
    ) async {
        let path = state.head.uri.split(separator: "?").first.map(String.init) ?? state.head.uri
        guard path == endpoint else {
            await writeResponse(
                .error(statusCode: 404, .invalidRequest("Not Found")),
                version: state.head.version,
                context: context
            )
            return
        }

        let request = makeHTTPRequest(from: state, path: path)
        let response = await requestHandler(request)
        await writeResponse(response, version: state.head.version, context: context)
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
    ) async {
        nonisolated(unsafe) let context = context
        let eventLoop = context.eventLoop
        let body = response.bodyData

        eventLoop.execute {
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
}
