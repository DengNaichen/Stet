import Foundation
import MCP

struct StetMCPHTTPResult: Sendable {
    nonisolated let statusCode: Int
    nonisolated let headers: [String: String]
    nonisolated let body: Data?

    nonisolated init(statusCode: Int, headers: [String: String], body: Data?) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

actor StetMCPProtocolServer {
    static let toolName = "stet_transcribe_audio"

    private let transcriber: any MCPTranscriptionServing
    private let transport: StatelessHTTPServerTransport
    private let server: Server
    private var started = false

    init(transcriber: any MCPTranscriptionServing) {
        self.transcriber = transcriber
        self.transport = StatelessHTTPServerTransport()
        self.server = Server(
            name: "stet",
            version: "1.0.0",
            title: "Stet Transcription",
            instructions: "Transcribe a readable local audio file with Stet and return clean text.",
            capabilities: .init(tools: .init(listChanged: false))
        )
    }

    func start() async throws {
        guard !started else { return }

        let transcriber = self.transcriber
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [Self.transcriptionTool])
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            await Self.callTool(parameters, transcriber: transcriber)
        }
        try await server.start(transport: transport)
        started = true
    }

    func stop() async {
        guard started else { return }
        await server.stop()
        started = false
    }

    func handleHTTPRequest(_ request: HTTPRequest) async -> HTTPResponse {
        await transport.handleRequest(request)
    }

    func handleRawRequest(
        method: String,
        headers: [String: String],
        body: Data?,
        path: String = "/mcp"
    ) async -> StetMCPHTTPResult {
        let response = await transport.handleRequest(
            HTTPRequest(method: method, headers: headers, body: body, path: path)
        )
        return StetMCPHTTPResult(
            statusCode: response.statusCode,
            headers: response.headers,
            body: response.bodyData
        )
    }

    private nonisolated static var transcriptionTool: Tool {
        Tool(
            name: toolName,
            title: "Transcribe audio with Stet",
            description:
                "Transcribes an absolute local audio file path with Stet's selected engine and applies the current rewrite settings. Use the returned text as the final transcript.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "audio_path": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to a readable local audio file."),
                    ])
                ]),
                "required": .array([.string("audio_path")]),
                "additionalProperties": .bool(false),
            ]),
            annotations: .init(
                title: "Transcribe audio with Stet",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            ),
            outputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "text": .object(["type": .string("string")]),
                    "raw_text": .object(["type": .string("string")]),
                    "language_code": .object(["type": .string("string")]),
                    "rewrite_applied": .object(["type": .string("boolean")]),
                    "warnings": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                    ]),
                ]),
                "required": .array([
                    .string("text"),
                    .string("raw_text"),
                    .string("language_code"),
                    .string("rewrite_applied"),
                    .string("warnings"),
                ]),
                "additionalProperties": .bool(false),
            ])
        )
    }

    private nonisolated static func callTool(
        _ parameters: CallTool.Parameters,
        transcriber: any MCPTranscriptionServing
    ) async -> CallTool.Result {
        guard parameters.name == toolName else {
            return toolError("Unknown tool: \(parameters.name)")
        }
        guard let audioPath = parameters.arguments?["audio_path"]?.stringValue,
            !audioPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return toolError("audio_path is required and must be a non-empty string.")
        }

        do {
            let output = try await transcriber.transcribe(audioPath: audioPath)
            return try CallTool.Result(
                content: [.text(text: output.text, annotations: nil, _meta: nil)],
                structuredContent: output,
                isError: false
            )
        } catch {
            return toolError(error.localizedDescription)
        }
    }

    private nonisolated static func toolError(_ message: String) -> CallTool.Result {
        CallTool.Result(
            content: [.text(text: message, annotations: nil, _meta: nil)],
            isError: true
        )
    }
}
