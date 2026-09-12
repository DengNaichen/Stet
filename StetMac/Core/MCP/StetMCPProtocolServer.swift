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
    static let listMeetingsToolName = "stet_list_meetings"
    static let listUnorganizedMeetingsToolName = "stet_list_unorganized_meetings"
    static let getMeetingTranscriptToolName = "stet_get_meeting_transcript"

    private let catalog: any MCPMeetingServing
    private let transport: StatelessHTTPServerTransport
    private let server: Server
    private var started = false

    init(catalog: any MCPMeetingServing) {
        self.catalog = catalog
        self.transport = StatelessHTTPServerTransport()
        self.server = Server(
            name: "stet",
            version: "1.0.0",
            title: "Stet Meetings",
            instructions:
                "Read meeting recordings already captured by Stet. Listing tools return metadata only. Use stet_get_meeting_transcript to fetch a saved transcript. Do not wait on transcription; Stet processes audio in the app.",
            capabilities: .init(tools: .init(listChanged: false))
        )
    }

    func start() async throws {
        guard !started else { return }

        let catalog = self.catalog
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [Self.listMeetingsTool, Self.listUnorganizedMeetingsTool, Self.getTranscriptTool])
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            await Self.callTool(parameters, catalog: catalog)
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

    private nonisolated static var meetingSummarySchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .string("string")]),
                "started_at": .object(["type": .string("string")]),
                "ended_at": .object(["type": .string("string")]),
                "duration_seconds": .object(["type": .string("number")]),
                "status": .object(["type": .string("string")]),
                "speaker_count": .object(["type": .string("integer")]),
                "failure_message": .object(["type": .string("string")]),
            ]),
            "required": .array([
                .string("id"),
                .string("started_at"),
                .string("duration_seconds"),
                .string("status"),
                .string("speaker_count"),
            ]),
            "additionalProperties": .bool(false),
        ])
    }

    private nonisolated static var meetingListOutputSchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "meetings": .object([
                    "type": .string("array"),
                    "items": meetingSummarySchema,
                ])
            ]),
            "required": .array([.string("meetings")]),
            "additionalProperties": .bool(false),
        ])
    }

    private nonisolated static var listLimitInputSchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Maximum number of meetings to return. Defaults to 20."),
                ])
            ]),
            "additionalProperties": .bool(false),
        ])
    }

    private nonisolated static var listMeetingsTool: Tool {
        Tool(
            name: listMeetingsToolName,
            title: "List Stet meetings",
            description:
                "Lists all Stet meeting recordings as metadata. Status is recording, processing, ready, organized, or failed. Use stet_get_meeting_transcript to fetch transcript text.",
            inputSchema: listLimitInputSchema,
            annotations: .init(
                title: "List Stet meetings",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            ),
            outputSchema: meetingListOutputSchema
        )
    }

    private nonisolated static var listUnorganizedMeetingsTool: Tool {
        Tool(
            name: listUnorganizedMeetingsToolName,
            title: "List unorganized Stet meetings",
            description:
                "Lists meetings that have finished recording and transcription but have not been organized yet (status ready). This is the inbox for meeting notes.",
            inputSchema: listLimitInputSchema,
            annotations: .init(
                title: "List unorganized Stet meetings",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            ),
            outputSchema: meetingListOutputSchema
        )
    }

    private nonisolated static var getTranscriptTool: Tool {
        Tool(
            name: getMeetingTranscriptToolName,
            title: "Get a Stet meeting transcript",
            description:
                "Returns a saved Stet meeting transcript. Pass meeting_id from a list tool, or omit it to get the most recent ready meeting. Does not run transcription.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "meeting_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Meeting folder name, such as 2026-09-12 16-20-01. Omit to use the most recent ready meeting."
                        ),
                    ])
                ]),
                "additionalProperties": .bool(false),
            ]),
            annotations: .init(
                title: "Get a Stet meeting transcript",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            ),
            outputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "id": .object(["type": .string("string")]),
                    "started_at": .object(["type": .string("string")]),
                    "ended_at": .object(["type": .string("string")]),
                    "duration_seconds": .object(["type": .string("number")]),
                    "status": .object(["type": .string("string")]),
                    "speaker_count": .object(["type": .string("integer")]),
                    "transcript": .object(["type": .string("string")]),
                    "failure_message": .object(["type": .string("string")]),
                ]),
                "required": .array([
                    .string("id"),
                    .string("started_at"),
                    .string("duration_seconds"),
                    .string("status"),
                    .string("speaker_count"),
                ]),
                "additionalProperties": .bool(false),
            ])
        )
    }

    private nonisolated static func callTool(
        _ parameters: CallTool.Parameters,
        catalog: any MCPMeetingServing
    ) async -> CallTool.Result {
        switch parameters.name {
        case listMeetingsToolName:
            return await list(parameters.arguments, catalog: catalog, unorganized: false)
        case listUnorganizedMeetingsToolName:
            return await list(parameters.arguments, catalog: catalog, unorganized: true)
        case getMeetingTranscriptToolName:
            return await transcript(parameters.arguments, catalog: catalog)
        default:
            return toolError("Unknown tool: \(parameters.name)")
        }
    }

    private nonisolated static func list(
        _ arguments: [String: Value]?,
        catalog: any MCPMeetingServing,
        unorganized: Bool
    ) async -> CallTool.Result {
        do {
            let limit = try parsedLimit(arguments)
            let output =
                unorganized
                ? try catalog.listUnorganizedMeetings(limit: limit)
                : try catalog.listMeetings(limit: limit)
            return try CallTool.Result(
                content: [.text(text: listContent(output.meetings), annotations: nil, _meta: nil)],
                structuredContent: output,
                isError: false
            )
        } catch {
            return toolError(error.localizedDescription)
        }
    }

    private nonisolated static func transcript(
        _ arguments: [String: Value]?,
        catalog: any MCPMeetingServing
    ) async -> CallTool.Result {
        let meetingID = arguments?["meeting_id"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedID = (meetingID?.isEmpty == false) ? meetingID : nil
        do {
            let output = try catalog.meetingTranscript(meetingID: resolvedID)
            let text = output.transcript ?? "Meeting \(output.id) is \(output.status)."
            return try CallTool.Result(
                content: [.text(text: text, annotations: nil, _meta: nil)],
                structuredContent: output,
                isError: false
            )
        } catch {
            return toolError(error.localizedDescription)
        }
    }

    private nonisolated static func parsedLimit(_ arguments: [String: Value]?) throws -> Int {
        guard let value = arguments?["limit"] else {
            return MCPMeetingCatalog.defaultLimit
        }
        let parsed: Int
        if let intValue = value.intValue {
            parsed = intValue
        } else if let doubleValue = value.doubleValue {
            parsed = Int(doubleValue)
        } else {
            throw MCPMeetingError.invalidLimit
        }
        return try MCPMeetingCatalog.resolvedLimit(parsed)
    }

    private nonisolated static func listContent(_ meetings: [MCPMeetingSummary]) -> String {
        if meetings.isEmpty {
            return "No meetings."
        }
        return meetings.map { meeting in
            "\(meeting.id)  \(meeting.status)"
        }.joined(separator: "\n")
    }

    private nonisolated static func toolError(_ message: String) -> CallTool.Result {
        CallTool.Result(
            content: [.text(text: message, annotations: nil, _meta: nil)],
            isError: true
        )
    }
}
