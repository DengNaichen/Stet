import Foundation
import MCP

struct MCPRecordingTools: Sendable {
    nonisolated static let listMeetingsToolName = "stet_list_meetings"
    nonisolated static let listUnorganizedMeetingsToolName = "stet_list_unorganized_meetings"
    nonisolated static let getMeetingTranscriptToolName = "stet_get_meeting_transcript"
    nonisolated static let names: Set<String> = [
        listMeetingsToolName, listUnorganizedMeetingsToolName, getMeetingTranscriptToolName,
    ]

    let catalog: any MCPMeetingServing

    nonisolated static var tools: [Tool] {
        [listMeetingsTool, listUnorganizedMeetingsTool, getTranscriptTool]
    }

    func call(_ parameters: CallTool.Parameters) async -> CallTool.Result {
        switch parameters.name {
        case Self.listMeetingsToolName:
            await list(parameters.arguments, unorganized: false)
        case Self.listUnorganizedMeetingsToolName:
            await list(parameters.arguments, unorganized: true)
        case Self.getMeetingTranscriptToolName:
            await transcript(parameters.arguments)
        default:
            MCPToolSupport.error("Unknown tool: \(parameters.name)")
        }
    }

    private func list(_ arguments: [String: Value]?, unorganized: Bool) async -> CallTool.Result {
        do {
            let limit = try parsedLimit(arguments)
            let output =
                unorganized
                ? try catalog.listUnorganizedMeetings(limit: limit)
                : try catalog.listMeetings(limit: limit)
            let text =
                output.meetings.isEmpty
                ? "No meetings."
                : output.meetings.map { "\($0.id)  \($0.status)" }.joined(separator: "\n")
            return try MCPToolSupport.result(text: text, output: output)
        } catch {
            return MCPToolSupport.error(error.localizedDescription)
        }
    }

    private func transcript(_ arguments: [String: Value]?) async -> CallTool.Result {
        let meetingID = arguments?["meeting_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let output = try catalog.meetingTranscript(meetingID: meetingID?.isEmpty == false ? meetingID : nil)
            return try MCPToolSupport.result(
                text: output.transcript ?? "Meeting \(output.id) is \(output.status).",
                output: output
            )
        } catch {
            return MCPToolSupport.error(error.localizedDescription)
        }
    }

    private nonisolated func parsedLimit(_ arguments: [String: Value]?) throws -> Int {
        guard let value = arguments?["limit"] else { return MCPMeetingCatalog.defaultLimit }
        let parsed = value.intValue ?? value.doubleValue.map(Int.init)
        guard let parsed else { throw MCPMeetingError.invalidLimit }
        return try MCPMeetingCatalog.resolvedLimit(parsed)
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
                .string("id"), .string("started_at"), .string("duration_seconds"), .string("status"),
                .string("speaker_count"),
            ]),
            "additionalProperties": .bool(false),
        ])
    }

    private nonisolated static var meetingListOutputSchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object(["meetings": .object(["type": .string("array"), "items": meetingSummarySchema])]),
            "required": .array([.string("meetings")]),
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
                title: "List Stet meetings", readOnlyHint: true, destructiveHint: false, idempotentHint: true,
                openWorldHint: false),
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
                title: "List unorganized Stet meetings", readOnlyHint: true, destructiveHint: false,
                idempotentHint: true, openWorldHint: false),
            outputSchema: meetingListOutputSchema
        )
    }

    private nonisolated static var getTranscriptTool: Tool {
        var properties = meetingSummarySchema.objectValue?["properties"]?.objectValue ?? [:]
        properties["transcript"] = .object(["type": .string("string")])
        return Tool(
            name: getMeetingTranscriptToolName,
            title: "Get a Stet meeting transcript",
            description:
                "Returns a saved Stet meeting transcript. Pass meeting_id from a list tool, or omit it to get the most recent ready meeting. Does not run transcription.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(["meeting_id": .object(["type": .string("string")])]),
                "additionalProperties": .bool(false),
            ]),
            annotations: .init(
                title: "Get a Stet meeting transcript", readOnlyHint: true, destructiveHint: false,
                idempotentHint: true, openWorldHint: false),
            outputSchema: .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array([
                    .string("id"), .string("started_at"), .string("duration_seconds"), .string("status"),
                    .string("speaker_count"),
                ]),
                "additionalProperties": .bool(false),
            ])
        )
    }
}
