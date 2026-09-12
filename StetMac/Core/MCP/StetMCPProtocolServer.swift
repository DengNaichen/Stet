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
    static let syncExpectedMeetingsToolName = "stet_sync_expected_meetings"

    private static let serverName = "stet"
    private static let serverVersion = "1.0.0"
    private static let serverTitle = "Stet Meetings"
    private static let serverInstructions =
        "Read meeting recordings captured by Stet and synchronize expected meetings for local reminders. Listing tools return metadata only. Use stet_get_meeting_transcript to fetch a saved transcript."
    private static let serverCapabilities = Server.Capabilities(tools: .init(listChanged: false))

    private let catalog: any MCPMeetingServing
    private let expectedMeetings: (any ExpectedMeetingServing)?
    private let transport: StatelessHTTPServerTransport
    private let server: Server
    private var started = false

    init(
        catalog: any MCPMeetingServing,
        expectedMeetings: (any ExpectedMeetingServing)? = nil
    ) {
        self.catalog = catalog
        self.expectedMeetings = expectedMeetings
        self.transport = StatelessHTTPServerTransport()
        self.server = Server(
            name: Self.serverName,
            version: Self.serverVersion,
            title: Self.serverTitle,
            instructions: Self.serverInstructions,
            capabilities: Self.serverCapabilities
        )
    }

    func start() async throws {
        guard !started else { return }

        let catalog = self.catalog
        let expectedMeetings = self.expectedMeetings
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [
                Self.listMeetingsTool,
                Self.listUnorganizedMeetingsTool,
                Self.getTranscriptTool,
                Self.syncExpectedMeetingsTool,
            ])
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            await Self.callTool(
                parameters,
                catalog: catalog,
                expectedMeetings: expectedMeetings
            )
        }
        try await server.start(transport: transport)
        // Stateless HTTP has no session. Cursor reconnects by sending initialize
        // again; the SDK's default handler rejects that for the process lifetime.
        await server.withMethodHandler(Initialize.self) { params in
            Self.initializeResult(requestedProtocolVersion: params.protocolVersion)
        }
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
                "metadata": meetingMetadataSchema,
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

    private nonisolated static var meetingMetadataSchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "expected_meeting_id": .object(["type": .string("string")]),
                "source": .object(["type": .string("string")]),
                "external_id": .object(["type": .string("string")]),
                "title": .object(["type": .string("string")]),
                "scheduled_start_at": .object(["type": .string("string")]),
                "scheduled_end_at": .object(["type": .string("string")]),
                "attendees": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "name": .object(["type": .string("string")]),
                            "email": .object(["type": .string("string")]),
                        ]),
                        "required": .array([.string("name")]),
                        "additionalProperties": .bool(false),
                    ]),
                ]),
                "meeting_url": .object(["type": .string("string")]),
            ]),
            "required": .array([.string("attendees")]),
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
                    "metadata": meetingMetadataSchema,
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

    private nonisolated static var syncExpectedMeetingsTool: Tool {
        Tool(
            name: syncExpectedMeetingsToolName,
            title: "Sync expected Stet meetings",
            description:
                "Reconciles a complete snapshot of expected meetings in a time window. Stet stores them separately from recordings and schedules a reminder five minutes before each meeting.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "window_start": .object(["type": .string("string"), "format": .string("date-time")]),
                    "window_end": .object(["type": .string("string"), "format": .string("date-time")]),
                    "meetings": .object([
                        "type": .string("array"),
                        "items": expectedMeetingInputSchema,
                    ]),
                ]),
                "required": .array([.string("window_start"), .string("window_end"), .string("meetings")]),
                "additionalProperties": .bool(false),
            ]),
            annotations: .init(
                title: "Sync expected Stet meetings",
                readOnlyHint: false,
                destructiveHint: true,
                idempotentHint: true,
                openWorldHint: false
            ),
            outputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "created": .object(["type": .string("integer")]),
                    "updated": .object(["type": .string("integer")]),
                    "cancelled": .object(["type": .string("integer")]),
                    "meetings": .object([
                        "type": .string("array"),
                        "items": expectedMeetingOutputSchema,
                    ]),
                ]),
                "required": .array([
                    .string("created"),
                    .string("updated"),
                    .string("cancelled"),
                    .string("meetings"),
                ]),
                "additionalProperties": .bool(false),
            ])
        )
    }

    private nonisolated static var expectedMeetingOutputSchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .string("string")]),
                "source": .object(["type": .string("string")]),
                "external_id": .object(["type": .string("string")]),
                "scheduled_start_at": .object(["type": .string("string")]),
                "scheduled_end_at": .object(["type": .string("string")]),
                "title": .object(["type": .string("string")]),
                "attendees": expectedMeetingInputSchema.objectValue?["properties"]?.objectValue?[
                    "attendees"
                ] ?? .object(["type": .string("array")]),
                "meeting_url": .object(["type": .string("string")]),
                "notes": .object(["type": .string("string")]),
                "source_modified_at": .object(["type": .string("string")]),
                "status": .object(["type": .string("string")]),
                "recorded_meeting_id": .object(["type": .string("string")]),
            ]),
            "required": .array([
                .string("id"),
                .string("source"),
                .string("external_id"),
                .string("scheduled_start_at"),
                .string("scheduled_end_at"),
                .string("attendees"),
                .string("status"),
            ]),
            "additionalProperties": .bool(false),
        ])
    }

    private nonisolated static var expectedMeetingInputSchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "source": .object(["type": .string("string")]),
                "external_id": .object(["type": .string("string")]),
                "scheduled_start_at": .object(["type": .string("string"), "format": .string("date-time")]),
                "scheduled_end_at": .object(["type": .string("string"), "format": .string("date-time")]),
                "title": .object(["type": .string("string")]),
                "attendees": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "name": .object(["type": .string("string")]),
                            "email": .object(["type": .string("string")]),
                        ]),
                        "required": .array([.string("name")]),
                        "additionalProperties": .bool(false),
                    ]),
                ]),
                "meeting_url": .object(["type": .string("string"), "format": .string("uri")]),
                "notes": .object(["type": .string("string")]),
                "source_modified_at": .object(["type": .string("string"), "format": .string("date-time")]),
                "status": .object([
                    "type": .string("string"),
                    "enum": .array([.string("scheduled"), .string("cancelled")]),
                ]),
            ]),
            "required": .array([
                .string("source"),
                .string("external_id"),
                .string("scheduled_start_at"),
                .string("scheduled_end_at"),
            ]),
            "additionalProperties": .bool(false),
        ])
    }

    private nonisolated static func initializeResult(requestedProtocolVersion: String) -> Initialize.Result {
        let protocolVersion =
            Version.supported.contains(requestedProtocolVersion)
            ? requestedProtocolVersion
            : Version.latest
        return Initialize.Result(
            protocolVersion: protocolVersion,
            capabilities: serverCapabilities,
            serverInfo: .init(
                name: serverName,
                version: serverVersion,
                title: serverTitle
            ),
            instructions: serverInstructions
        )
    }

    private nonisolated static func callTool(
        _ parameters: CallTool.Parameters,
        catalog: any MCPMeetingServing,
        expectedMeetings: (any ExpectedMeetingServing)?
    ) async -> CallTool.Result {
        switch parameters.name {
        case listMeetingsToolName:
            return await list(parameters.arguments, catalog: catalog, unorganized: false)
        case listUnorganizedMeetingsToolName:
            return await list(parameters.arguments, catalog: catalog, unorganized: true)
        case getMeetingTranscriptToolName:
            return await transcript(parameters.arguments, catalog: catalog)
        case syncExpectedMeetingsToolName:
            return await syncExpectedMeetings(parameters.arguments, service: expectedMeetings)
        default:
            return toolError("Unknown tool: \(parameters.name)")
        }
    }

    private nonisolated static func syncExpectedMeetings(
        _ arguments: [String: Value]?,
        service: (any ExpectedMeetingServing)?
    ) async -> CallTool.Result {
        guard let service else { return toolError("Expected meeting synchronization is unavailable.") }
        do {
            let arguments = arguments ?? [:]
            let windowStart = try requiredDate("window_start", in: arguments)
            let windowEnd = try requiredDate("window_end", in: arguments)
            guard let values = arguments["meetings"]?.arrayValue else {
                throw ExpectedMeetingError.invalidMeeting("meetings must be an array.")
            }
            let inputs = try values.map(parseExpectedMeeting)
            let result = try await service.sync(
                windowStart: windowStart,
                windowEnd: windowEnd,
                inputs: inputs
            )
            let output = MCPExpectedMeetingSyncOutput(result)
            return try CallTool.Result(
                content: [
                    .text(
                        text:
                            "Synced \(output.meetings.count) expected meetings: \(output.created) created, \(output.updated) updated, \(output.cancelled) cancelled.",
                        annotations: nil,
                        _meta: nil
                    )
                ],
                structuredContent: output,
                isError: false
            )
        } catch {
            return toolError(error.localizedDescription)
        }
    }

    private struct MCPExpectedMeetingSyncOutput: Codable, Sendable {
        let created: Int
        let updated: Int
        let cancelled: Int
        let meetings: [MCPExpectedMeetingOutput]

        init(_ result: ExpectedMeetingSyncResult) {
            self.created = result.created
            self.updated = result.updated
            self.cancelled = result.cancelled
            self.meetings = result.meetings.map(MCPExpectedMeetingOutput.init)
        }
    }

    private struct MCPExpectedMeetingOutput: Codable, Sendable {
        let id: UUID
        let source: String
        let externalID: String
        let scheduledStartAt: String
        let scheduledEndAt: String
        let title: String?
        let attendees: [MeetingAttendee]
        let meetingURL: URL?
        let notes: String?
        let sourceModifiedAt: String?
        let status: ExpectedMeetingStatus
        let recordedMeetingID: String?

        init(_ meeting: ExpectedMeeting) {
            self.id = meeting.id
            self.source = meeting.source
            self.externalID = meeting.externalID
            self.scheduledStartAt = Self.iso8601String(meeting.scheduledStartAt)
            self.scheduledEndAt = Self.iso8601String(meeting.scheduledEndAt)
            self.title = meeting.title
            self.attendees = meeting.attendees
            self.meetingURL = meeting.meetingURL
            self.notes = meeting.notes
            self.sourceModifiedAt = meeting.sourceModifiedAt.map(Self.iso8601String)
            self.status = meeting.status
            self.recordedMeetingID = meeting.recordedMeetingID
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case source
            case externalID = "external_id"
            case scheduledStartAt = "scheduled_start_at"
            case scheduledEndAt = "scheduled_end_at"
            case title
            case attendees
            case meetingURL = "meeting_url"
            case notes
            case sourceModifiedAt = "source_modified_at"
            case status
            case recordedMeetingID = "recorded_meeting_id"
        }

        private nonisolated static func iso8601String(_ date: Date) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.string(from: date)
        }
    }

    private nonisolated static func parseExpectedMeeting(_ value: Value) throws -> ExpectedMeetingInput {
        guard let object = value.objectValue else {
            throw ExpectedMeetingError.invalidMeeting("Each meeting must be an object.")
        }
        let source = try requiredString("source", in: object)
        let externalID = try requiredString("external_id", in: object)
        let attendees = try (object["attendees"]?.arrayValue ?? []).map { attendee in
            guard let object = attendee.objectValue else {
                throw ExpectedMeetingError.invalidMeeting("Each attendee must be an object.")
            }
            return MeetingAttendee(
                name: try requiredString("name", in: object),
                email: object["email"]?.stringValue
            )
        }
        let rawStatus = object["status"]?.stringValue ?? ExpectedMeetingStatus.scheduled.rawValue
        guard let status = ExpectedMeetingStatus(rawValue: rawStatus), status == .scheduled || status == .cancelled
        else {
            throw ExpectedMeetingError.invalidMeeting("status must be scheduled or cancelled.")
        }
        let meetingURL: URL?
        if let rawURL = object["meeting_url"]?.stringValue {
            guard let parsedURL = URL(string: rawURL) else {
                throw ExpectedMeetingError.invalidMeeting("meeting_url must be a valid URL.")
            }
            meetingURL = parsedURL
        } else {
            meetingURL = nil
        }
        return ExpectedMeetingInput(
            source: source,
            externalID: externalID,
            scheduledStartAt: try requiredDate("scheduled_start_at", in: object),
            scheduledEndAt: try requiredDate("scheduled_end_at", in: object),
            title: object["title"]?.stringValue,
            attendees: attendees,
            meetingURL: meetingURL,
            notes: object["notes"]?.stringValue,
            sourceModifiedAt: try optionalDate("source_modified_at", in: object),
            status: status
        )
    }

    private nonisolated static func requiredString(
        _ key: String,
        in object: [String: Value]
    ) throws -> String {
        guard let value = object[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            throw ExpectedMeetingError.invalidMeeting("\(key) is required.")
        }
        return value
    }

    private nonisolated static func requiredDate(
        _ key: String,
        in object: [String: Value]
    ) throws -> Date {
        guard let date = try optionalDate(key, in: object) else {
            throw ExpectedMeetingError.invalidMeeting("\(key) is required.")
        }
        return date
    }

    private nonisolated static func optionalDate(
        _ key: String,
        in object: [String: Value]
    ) throws -> Date? {
        guard let raw = object[key]?.stringValue else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: raw) else {
            throw ExpectedMeetingError.invalidMeeting("\(key) must be an ISO 8601 date-time.")
        }
        return date
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
