import Foundation
import MCP

struct MCPExpectedMeetingTools: Sendable {
    nonisolated static let listExpectedMeetingsToolName = "stet_list_expected_meetings"
    nonisolated static let getExpectedMeetingToolName = "stet_get_expected_meeting"
    nonisolated static let names: Set<String> = [
        listExpectedMeetingsToolName, getExpectedMeetingToolName,
    ]

    let service: (any ExpectedMeetingServing)?

    nonisolated static var tools: [Tool] { [listTool, getTool] }

    func call(_ parameters: CallTool.Parameters) async -> CallTool.Result {
        guard let service else {
            return MCPToolSupport.error("Expected meeting access is unavailable.")
        }
        do {
            switch parameters.name {
            case Self.listExpectedMeetingsToolName:
                return try await list(parameters.arguments, service: service)
            case Self.getExpectedMeetingToolName:
                return try await get(parameters.arguments, service: service)
            default:
                return MCPToolSupport.error("Unknown tool: \(parameters.name)")
            }
        } catch {
            return MCPToolSupport.error(error.localizedDescription)
        }
    }

    private func list(
        _ rawArguments: [String: Value]?,
        service: any ExpectedMeetingServing
    ) async throws -> CallTool.Result {
        let arguments = rawArguments ?? [:]
        let from = try requiredDate("from", in: arguments)
        let to = try requiredDate("to", in: arguments)
        let meetings = try await service.meetings(from: from, to: to)
        let output = ListOutput(meetings: meetings.map(MeetingOutput.init))
        return try MCPToolSupport.result(text: "Found \(meetings.count) expected meetings.", output: output)
    }

    private func get(
        _ rawArguments: [String: Value]?,
        service: any ExpectedMeetingServing
    ) async throws -> CallTool.Result {
        let arguments = rawArguments ?? [:]
        let rawID = try MCPToolSupport.requiredString("id", in: arguments)
        guard let id = UUID(uuidString: rawID), let meeting = await service.meeting(id: id) else {
            throw MCPToolInputError.invalid("No expected meeting found with id \(rawID).")
        }
        return try MCPToolSupport.result(text: meeting.title ?? "Untitled meeting", output: MeetingOutput(meeting))
    }

    private nonisolated struct ListOutput: Codable, Sendable {
        let meetings: [MeetingOutput]
    }

    private nonisolated func requiredDate(_ key: String, in values: [String: Value]) throws -> Date {
        guard let date = try MCPToolSupport.date(key, in: values) else {
            throw MCPToolInputError.invalid("\(key) is required.")
        }
        return date
    }

    private nonisolated struct MeetingOutput: Codable, Sendable {
        let id: UUID
        let source: String
        let externalID: String
        let scheduledStartAt: String
        let scheduledEndAt: String
        let title: String?
        let attendees: [AttendeeOutput]
        let meetingURL: String?
        let notes: String?
        let sourceModifiedAt: String?
        let status: String
        let recordedMeetingID: String?

        init(_ meeting: ExpectedMeeting) {
            id = meeting.id
            source = meeting.source
            externalID = meeting.externalID
            scheduledStartAt = MCPToolSupport.iso8601(meeting.scheduledStartAt)
            scheduledEndAt = MCPToolSupport.iso8601(meeting.scheduledEndAt)
            title = meeting.title
            attendees = meeting.attendees.map { AttendeeOutput(name: $0.name, email: $0.email) }
            meetingURL = meeting.meetingURL?.absoluteString
            notes = meeting.notes
            sourceModifiedAt = meeting.sourceModifiedAt.map(MCPToolSupport.iso8601)
            status = meeting.status.rawValue
            recordedMeetingID = meeting.recordedMeetingID
        }

        private enum CodingKeys: String, CodingKey {
            case id, source, title, attendees, notes, status
            case externalID = "external_id"
            case scheduledStartAt = "scheduled_start_at"
            case scheduledEndAt = "scheduled_end_at"
            case meetingURL = "meeting_url"
            case sourceModifiedAt = "source_modified_at"
            case recordedMeetingID = "recorded_meeting_id"
        }
    }

    private nonisolated struct AttendeeOutput: Codable, Sendable {
        let name: String
        let email: String?
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
                "attendees": .object(["type": .string("array")]),
                "meeting_url": .object(["type": .string("string")]),
                "notes": .object(["type": .string("string")]),
                "source_modified_at": .object(["type": .string("string")]),
                "status": .object(["type": .string("string")]),
                "recorded_meeting_id": .object(["type": .string("string")]),
            ]),
            "required": .array([
                .string("id"), .string("source"), .string("external_id"), .string("scheduled_start_at"),
                .string("scheduled_end_at"), .string("attendees"), .string("status"),
            ]),
            "additionalProperties": .bool(false),
        ])
    }

    private nonisolated static var listTool: Tool {
        Tool(
            name: listExpectedMeetingsToolName,
            title: "List expected Stet meetings",
            description: "Lists expected meetings in a bounded date range for meeting preparation.",
            inputSchema: dateRangeInputSchema,
            annotations: .init(
                title: "List expected Stet meetings", readOnlyHint: true, destructiveHint: false,
                idempotentHint: true, openWorldHint: false
            ),
            outputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "meetings": .object(["type": .string("array"), "items": expectedMeetingOutputSchema])
                ]),
                "required": .array([.string("meetings")]),
                "additionalProperties": .bool(false),
            ])
        )
    }

    private nonisolated static var getTool: Tool {
        Tool(
            name: getExpectedMeetingToolName,
            title: "Get an expected Stet meeting",
            description: "Returns one expected meeting by its Stet UUID.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(["id": .object(["type": .string("string")])]),
                "required": .array([.string("id")]),
                "additionalProperties": .bool(false),
            ]),
            annotations: .init(
                title: "Get an expected Stet meeting", readOnlyHint: true, destructiveHint: false,
                idempotentHint: true, openWorldHint: false
            ),
            outputSchema: expectedMeetingOutputSchema
        )
    }

    private nonisolated static var dateRangeInputSchema: Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "from": .object(["type": .string("string"), "format": .string("date-time")]),
                "to": .object(["type": .string("string"), "format": .string("date-time")]),
            ]),
            "required": .array([.string("from"), .string("to")]),
            "additionalProperties": .bool(false),
        ])
    }
}
