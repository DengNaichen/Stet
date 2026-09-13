import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Stet MCP Protocol Server")
struct StetMCPProtocolServerTests {
    @Test func listsMeetingTools() async throws {
        let server = StetMCPProtocolServer(catalog: MCPStubMeetingCatalog())
        try await server.start()
        defer { Task { await server.stop() } }
        try await initialize(server)

        let listResponse = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/list",
                "params": [:],
            ])
        )
        #expect(listResponse.statusCode == 200)
        let listJSON = try responseJSON(listResponse)
        let listResult = try #require(listJSON["result"] as? [String: Any])
        let tools = try #require(listResult["tools"] as? [[String: Any]])
        #expect(
            tools.map { $0["name"] as? String } == [
                StetMCPProtocolServer.listMeetingsToolName,
                StetMCPProtocolServer.listUnorganizedMeetingsToolName,
                StetMCPProtocolServer.getMeetingTranscriptToolName,
                MCPExpectedMeetingTools.listExpectedMeetingsToolName,
                MCPExpectedMeetingTools.getExpectedMeetingToolName,
            ])
        #expect(tools.allSatisfy { $0["inputSchema"] != nil && $0["outputSchema"] != nil })
    }

    @Test func callsMeetingToolsAndReturnsStructuredContent() async throws {
        let catalog = MCPStubMeetingCatalog()
        let server = StetMCPProtocolServer(catalog: catalog)
        try await server.start()
        defer { Task { await server.stop() } }
        try await initialize(server)

        let listResponse = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": [
                    "name": StetMCPProtocolServer.listMeetingsToolName,
                    "arguments": ["limit": 5],
                ],
            ])
        )
        let listResult = try #require(try responseJSON(listResponse)["result"] as? [String: Any])
        #expect(listResult["isError"] as? Bool == false)
        let listStructured = try #require(listResult["structuredContent"] as? [String: Any])
        let meetings = try #require(listStructured["meetings"] as? [[String: Any]])
        #expect(meetings.first?["id"] as? String == "2026-09-12 16-20-01")
        #expect(meetings.first?["status"] as? String == "ready")

        let inboxResponse = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": [
                    "name": StetMCPProtocolServer.listUnorganizedMeetingsToolName,
                    "arguments": [:],
                ],
            ])
        )
        let inboxResult = try #require(try responseJSON(inboxResponse)["result"] as? [String: Any])
        #expect(inboxResult["isError"] as? Bool == false)

        let getResponse = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 4,
                "method": "tools/call",
                "params": [
                    "name": StetMCPProtocolServer.getMeetingTranscriptToolName,
                    "arguments": ["meeting_id": "2026-09-12 16-20-01"],
                ],
            ])
        )
        let getResult = try #require(try responseJSON(getResponse)["result"] as? [String: Any])
        #expect(getResult["isError"] as? Bool == false)
        let content = try #require(getResult["content"] as? [[String: Any]])
        #expect(content.first?["text"] as? String == "hello from the room")
        let structured = try #require(getResult["structuredContent"] as? [String: Any])
        #expect(structured["transcript"] as? String == "hello from the room")
        #expect(structured["id"] as? String == "2026-09-12 16-20-01")
    }

    @Test func listsAndGetsExpectedMeetingsThroughMCP() async throws {
        let start = Date(timeIntervalSince1970: 1_789_156_800)
        let expected = ExpectedMeeting(
            id: UUID(),
            source: "calendar:source-1:calendar-1",
            externalID: "event-1",
            scheduledStartAt: start,
            scheduledEndAt: start.addingTimeInterval(3_600),
            title: "Project sync",
            attendees: [MeetingAttendee(name: "Taylor", email: "taylor@example.com")],
            meetingURL: URL(string: "https://example.com/meeting"),
            notes: "Review status",
            sourceModifiedAt: nil,
            status: .scheduled,
            recordedMeetingID: nil
        )
        let server = StetMCPProtocolServer(
            catalog: MCPStubMeetingCatalog(),
            expectedMeetings: MCPExpectedMeetingStub(meetings: [expected])
        )
        try await server.start()
        defer { Task { await server.stop() } }
        try await initialize(server)

        let listResponse = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": [
                    "name": MCPExpectedMeetingTools.listExpectedMeetingsToolName,
                    "arguments": [
                        "from": "2026-09-12T00:00:00+08:00",
                        "to": "2026-09-14T00:00:00+08:00",
                    ],
                ],
            ])
        )
        let listResult = try #require(try responseJSON(listResponse)["result"] as? [String: Any])
        let listStructured = try #require(listResult["structuredContent"] as? [String: Any])
        let meetings = try #require(listStructured["meetings"] as? [[String: Any]])
        #expect(meetings.first?["title"] as? String == "Project sync")

        let getResponse = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": [
                    "name": MCPExpectedMeetingTools.getExpectedMeetingToolName,
                    "arguments": ["id": expected.id.uuidString],
                ],
            ])
        )
        let getResult = try #require(try responseJSON(getResponse)["result"] as? [String: Any])
        let getStructured = try #require(getResult["structuredContent"] as? [String: Any])
        #expect(getStructured["external_id"] as? String == "event-1")
    }

    @Test func unknownToolInvalidLimitAndCatalogFailuresAreToolErrors() async throws {
        let catalog = MCPStubMeetingCatalog(error: MCPMeetingError.noReadyMeeting)
        let server = StetMCPProtocolServer(catalog: catalog)
        try await server.start()
        defer { Task { await server.stop() } }
        try await initialize(server)

        let unknown = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": [
                    "name": "stet_transcribe_audio",
                    "arguments": [:],
                ],
            ])
        )
        let unknownResult = try #require(try responseJSON(unknown)["result"] as? [String: Any])
        #expect(unknownResult["isError"] as? Bool == true)

        let invalidLimit = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": [
                    "name": StetMCPProtocolServer.listMeetingsToolName,
                    "arguments": ["limit": 0],
                ],
            ])
        )
        let invalidLimitResult = try #require(
            try responseJSON(invalidLimit)["result"] as? [String: Any]
        )
        #expect(invalidLimitResult["isError"] as? Bool == true)

        let emptyInbox = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 4,
                "method": "tools/call",
                "params": [
                    "name": StetMCPProtocolServer.getMeetingTranscriptToolName,
                    "arguments": [:],
                ],
            ])
        )
        let emptyInboxResult = try #require(
            try responseJSON(emptyInbox)["result"] as? [String: Any]
        )
        #expect(emptyInboxResult["isError"] as? Bool == true)
    }

    @Test func initializeIsIdempotentForClientReconnects() async throws {
        let server = StetMCPProtocolServer(catalog: MCPStubMeetingCatalog())
        try await server.start()
        defer { Task { await server.stop() } }

        try await initialize(server, id: 1)
        try await initialize(server, id: 2)

        let listResponse = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/list",
                "params": [:],
            ])
        )
        #expect(listResponse.statusCode == 200)
        let listJSON = try responseJSON(listResponse)
        #expect(listJSON["error"] == nil)
        let listResult = try #require(listJSON["result"] as? [String: Any])
        let tools = try #require(listResult["tools"] as? [[String: Any]])
        #expect(tools.count == 5)
    }

    @Test func initializeAcceptsStreamableHTTPAcceptHeader() async throws {
        let server = StetMCPProtocolServer(catalog: MCPStubMeetingCatalog())
        try await server.start()
        defer { Task { await server.stop() } }

        try await initialize(
            server,
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json, text/event-stream",
            ]
        )
    }

    @Test func calendarToolsRespectReadAndWriteCapabilities() async throws {
        let calendar = MCPCalendarStub()
        let readServer = StetMCPProtocolServer(
            catalog: MCPStubMeetingCatalog(),
            calendarReadClient: calendar
        )
        try await readServer.start()
        defer { Task { await readServer.stop() } }
        try await initialize(readServer)

        let readNames = try await listedToolNames(readServer)
        #expect(Set(readNames).isSuperset(of: MCPCalendarTools.readNames))
        #expect(Set(readNames).isDisjoint(with: MCPCalendarTools.writeNames))

        let writeServer = StetMCPProtocolServer(
            catalog: MCPStubMeetingCatalog(),
            calendarWriteClient: calendar
        )
        try await writeServer.start()
        defer { Task { await writeServer.stop() } }
        try await initialize(writeServer)
        let writeNames = try await listedToolNames(writeServer)
        #expect(Set(writeNames).isSuperset(of: MCPCalendarTools.readNames.union(MCPCalendarTools.writeNames)))
    }

    @Test func calendarFetchSupportsDateOnlyAndReturnsWireDTO() async throws {
        let calendar = MCPCalendarStub()
        let server = StetMCPProtocolServer(
            catalog: MCPStubMeetingCatalog(),
            calendarReadClient: calendar
        )
        try await server.start()
        defer { Task { await server.stop() } }
        try await initialize(server)

        let result = try await callTool(
            server,
            name: MCPCalendarTools.fetchEventsToolName,
            arguments: [
                "from": "2026-09-12",
                "to": "2026-09-13",
                "calendar_ids": ["calendar-1"],
                "include_all_day": true,
            ]
        )
        #expect(result["isError"] as? Bool == false)
        let query = try #require(calendar.lastQuery)
        #expect(query.calendarIDs == ["calendar-1"])
        #expect(query.endAt.timeIntervalSince(query.startAt) == 2 * 24 * 60 * 60)
        let structured = try #require(result["structuredContent"] as? [String: Any])
        let events = try #require(structured["events"] as? [[String: Any]])
        #expect(events.first?["title"] as? String == "Recurring sync")
        #expect(events.first?["occurrence_start"] as? String != nil)
        #expect(events.first?["original_start_at"] as? String != nil)
    }

    @Test func calendarWritesPassCreateClearAndRecurringIdentity() async throws {
        let calendar = MCPCalendarStub()
        let server = StetMCPProtocolServer(
            catalog: MCPStubMeetingCatalog(),
            calendarWriteClient: calendar
        )
        try await server.start()
        defer { Task { await server.stop() } }
        try await initialize(server)

        let fetched = try await callTool(
            server,
            name: MCPCalendarTools.fetchEventsToolName,
            arguments: [
                "from": "2026-09-12T00:00:00Z",
                "to": "2026-09-13T00:00:00Z",
                "calendar_ids": ["calendar-1"],
            ]
        )
        let fetchedContent = try #require(fetched["structuredContent"] as? [String: Any])
        let fetchedEvents = try #require(fetchedContent["events"] as? [[String: Any]])
        let wireEvent = try #require(fetchedEvents.first)
        let id = try #require(wireEvent["id"] as? String)
        let occurrenceStart = try #require(wireEvent["occurrence_start"] as? String)
        let originalStart = try #require(wireEvent["original_start_at"] as? String)

        _ = try await callTool(
            server,
            name: MCPCalendarTools.getEventToolName,
            arguments: [
                "id": id,
                "occurrence_start": occurrenceStart,
                "original_start_at": originalStart,
            ]
        )
        #expect(calendar.updatedIdentity?.occurrence?.isDetached == true)

        _ = try await callTool(
            server,
            name: MCPCalendarTools.createEventToolName,
            arguments: [
                "calendar_id": "calendar-1",
                "title": "All day",
                "start_at": "2026-09-14",
                "end_at": "2026-09-15",
                "is_all_day": true,
                "availability": "free",
                "url": "https://example.com/event",
                "time_zone": "Asia/Shanghai",
                "alarms": [
                    ["type": "relative", "minutes": 15, "email_address": "me@example.com"],
                    ["type": "absolute", "at": "2026-09-13T08:00:00Z"],
                    [
                        "type": "proximity", "location_title": "Office", "latitude": 31.2,
                        "longitude": 121.5, "proximity": "leave",
                    ],
                ],
                "recurrence": [
                    "frequency": "monthly", "interval": 2, "by_day": ["MO", "-1FR"],
                    "occurrence_count": 8,
                ],
            ]
        )
        #expect(calendar.createdRequest?.isAllDay == true)
        #expect(calendar.createdRequest?.availability == .free)
        #expect(calendar.createdRequest?.endAt.timeIntervalSince(calendar.createdRequest!.startAt) == 86_400)
        #expect(calendar.createdRequest?.timeZoneIdentifier == "Asia/Shanghai")
        #expect(calendar.createdRequest?.alarms.count == 3)
        #expect(calendar.createdRequest?.recurrenceRules.first?.interval == 2)

        _ = try await callTool(
            server,
            name: MCPCalendarTools.updateEventToolName,
            arguments: [
                "id": id,
                "occurrence_start": occurrenceStart,
                "original_start_at": originalStart,
                "location": NSNull(),
                "url": NSNull(),
                "notes": NSNull(),
                "span": "future_events",
            ]
        )
        #expect(calendar.updatedIdentity?.occurrence?.isDetached == true)
        if case .futureEvents? = calendar.updatedSpan {} else { Issue.record("Expected future_events span") }
        #expect(calendar.updatedRequest?.location == .clear)
        #expect(calendar.updatedRequest?.url == .clear)
        #expect(calendar.updatedRequest?.notes == .clear)

        _ = try await callTool(
            server,
            name: MCPCalendarTools.deleteEventToolName,
            arguments: [
                "id": id,
                "occurrence_start": occurrenceStart,
                "original_start_at": originalStart,
                "span": "this_event",
                "confirm": true,
            ]
        )
        #expect(calendar.deletedIdentity?.occurrence != nil)
        if case .thisEvent? = calendar.deletedSpan {} else { Issue.record("Expected this_event span") }
    }

    @Test func calendarRejectsUnsafeRecurringMutationsAndEmptyUpdates() async throws {
        let calendar = MCPCalendarStub()
        let server = StetMCPProtocolServer(catalog: MCPStubMeetingCatalog(), calendarWriteClient: calendar)
        try await server.start()
        defer { Task { await server.stop() } }
        try await initialize(server)

        let fetched = try await callTool(
            server, name: MCPCalendarTools.fetchEventsToolName,
            arguments: ["from": "2026-09-12", "to": "2026-09-12"])
        let content = try #require(fetched["structuredContent"] as? [String: Any])
        let event = try #require((content["events"] as? [[String: Any]])?.first)
        let id = try #require(event["id"] as? String)

        let unsafe = try await callTool(
            server, name: MCPCalendarTools.updateEventToolName,
            arguments: ["id": id, "title": "Unsafe"])
        #expect(unsafe["isError"] as? Bool == true)

        let empty = try await callTool(
            server, name: MCPCalendarTools.updateEventToolName,
            arguments: [
                "id": id,
                "occurrence_start": event["occurrence_start"] as Any,
                "original_start_at": event["original_start_at"] as Any,
            ])
        #expect(empty["isError"] as? Bool == true)

        for (field, invalidValue) in [
            ("notes", 42 as Any),
            ("url", false as Any),
            ("alarms", ["invalid": true] as Any),
            ("recurrence", [] as Any),
        ] {
            let result = try await callTool(
                server,
                name: MCPCalendarTools.updateEventToolName,
                arguments: [
                    "id": id,
                    "occurrence_start": event["occurrence_start"] as Any,
                    "original_start_at": event["original_start_at"] as Any,
                    field: invalidValue,
                ]
            )
            #expect(result["isError"] as? Bool == true)
        }
    }

    private let protocolVersion = "2025-11-25"

    private var baseHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ]
    }

    private var protocolHeaders: [String: String] {
        baseHeaders.merging(["MCP-Protocol-Version": protocolVersion]) { _, new in new }
    }

    private func initialize(
        _ server: StetMCPProtocolServer,
        headers: [String: String]? = nil,
        id: Int = 1
    ) async throws {
        let response = await server.handleRawRequest(
            method: "POST",
            headers: headers ?? baseHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": id,
                "method": "initialize",
                "params": [
                    "protocolVersion": protocolVersion,
                    "capabilities": [:],
                    "clientInfo": ["name": "StetTests", "version": "1.0"],
                ],
            ])
        )
        #expect(response.statusCode == 200)
        let json = try responseJSON(response)
        #expect(json["error"] == nil)
        let result = try #require(json["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == protocolVersion)
        let serverInfo = try #require(result["serverInfo"] as? [String: Any])
        #expect(serverInfo["name"] as? String == "stet")
    }

    private func listedToolNames(_ server: StetMCPProtocolServer) async throws -> [String] {
        let response = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData(["jsonrpc": "2.0", "id": 20, "method": "tools/list", "params": [:]])
        )
        let result = try #require(try responseJSON(response)["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        return tools.compactMap { $0["name"] as? String }
    }

    private func callTool(
        _ server: StetMCPProtocolServer,
        name: String,
        arguments: [String: Any]
    ) async throws -> [String: Any] {
        let response = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 21,
                "method": "tools/call",
                "params": ["name": name, "arguments": arguments],
            ])
        )
        return try #require(try responseJSON(response)["result"] as? [String: Any])
    }
}

private struct MCPStubMeetingCatalog: MCPMeetingServing {
    var error: MCPMeetingError?
    var summary = MCPMeetingSummary(
        id: "2026-09-12 16-20-01",
        startedAt: "2026-09-12T08:20:01Z",
        endedAt: "2026-09-12T08:45:12Z",
        durationSeconds: 1511,
        status: "ready",
        speakerCount: 2,
        failureMessage: nil,
        metadata: nil
    )

    func listMeetings(limit: Int) throws -> MCPMeetingListOutput {
        if let error { throw error }
        return MCPMeetingListOutput(meetings: Array([summary].prefix(limit)))
    }

    func listUnorganizedMeetings(limit: Int) throws -> MCPMeetingListOutput {
        try listMeetings(limit: limit)
    }

    func meetingTranscript(meetingID: String?) throws -> MCPMeetingTranscriptOutput {
        if let error { throw error }
        return MCPMeetingTranscriptOutput(
            id: meetingID ?? summary.id,
            startedAt: summary.startedAt,
            endedAt: summary.endedAt,
            durationSeconds: summary.durationSeconds,
            status: summary.status,
            speakerCount: summary.speakerCount,
            transcript: "hello from the room",
            failureMessage: nil,
            metadata: nil
        )
    }
}

private actor MCPExpectedMeetingStub: ExpectedMeetingServing {
    private var storedMeetings: [ExpectedMeeting]

    init(meetings: [ExpectedMeeting] = []) {
        storedMeetings = meetings
    }

    func sync(
        sourceScope: String,
        windowStart: Date,
        windowEnd: Date,
        inputs: [ExpectedMeetingInput]
    ) -> ExpectedMeetingSyncResult {
        return ExpectedMeetingSyncResult(created: inputs.count, updated: 0, cancelled: 0, meetings: [])
    }

    func meetings(from startAt: Date, to endAt: Date) -> [ExpectedMeeting] {
        storedMeetings.filter { $0.scheduledStartAt >= startAt && $0.scheduledStartAt < endAt }
    }

    func meeting(id: UUID) -> ExpectedMeeting? { storedMeetings.first { $0.id == id } }
    func skip(id: UUID) throws {}
    func markRecorded(id: UUID, meetingID: String) async throws {}
    func markCompleted(id: UUID) throws {}
    func restoreReminders() {}
}

@MainActor
private final class MCPCalendarStub: CalendarWriteClient {
    private(set) var lastQuery: CalendarEventQuery?
    private(set) var createdRequest: CalendarEventCreateRequest?
    private(set) var updatedIdentity: CalendarEventIdentity?
    private(set) var updatedRequest: CalendarEventUpdateRequest?
    private(set) var updatedSpan: CalendarEventMutationSpan?
    private(set) var deletedIdentity: CalendarEventIdentity?
    private(set) var deletedSpan: CalendarEventMutationSpan?

    private let sampleEvent: CalendarEvent

    init() {
        let start = Date(timeIntervalSince1970: 1_789_156_800)
        sampleEvent = CalendarEvent(
            identity: CalendarEventIdentity(
                eventID: "event-1",
                calendarID: "calendar-1",
                sourceID: "source-1",
                occurrence: CalendarOccurrenceIdentity(
                    occurrenceStart: start,
                    originalStart: start.addingTimeInterval(-7 * 24 * 60 * 60),
                    isDetached: true
                )
            ),
            title: "Recurring sync",
            startAt: start,
            endAt: start.addingTimeInterval(3600),
            isAllDay: false,
            status: .confirmed,
            availability: .busy,
            location: "Room",
            url: URL(string: "https://example.com"),
            notes: "Agenda",
            calendarTitle: "Work",
            timeZoneIdentifier: "Asia/Shanghai",
            modifiedAt: nil,
            alarms: [
                CalendarAlarm(
                    kind: .relative, relativeOffsetMinutes: -15, absoluteAt: nil, proximity: nil,
                    locationTitle: nil, latitude: nil, longitude: nil, radius: nil,
                    action: .display, emailAddress: "me@example.com", soundName: nil)
            ],
            recurrenceRules: [CalendarRecurrenceRule(frequency: .weekly, daysOfTheWeek: [.init(day: .monday)])],
            organizer: nil,
            attendees: []
        )
    }

    func authorizationStatus() -> CalendarAuthorizationStatus { .fullAccess }
    func requestFullAccess() async throws -> Bool { true }
    func defaultCalendarID() throws -> String? { "calendar-1" }
    func calendars() throws -> [CalendarRecord] {
        [
            CalendarRecord(
                id: "calendar-1",
                title: "Work",
                source: CalendarSourceRecord(id: "source-1", title: "Local", type: .local),
                colorHex: "#123456",
                isEditable: true,
                isSubscribed: false
            )
        ]
    }
    func events(matching query: CalendarEventQuery) throws -> [CalendarEvent] {
        lastQuery = query
        return [sampleEvent]
    }
    func event(_ identity: CalendarEventIdentity) throws -> CalendarEvent {
        updatedIdentity = identity
        return sampleEvent
    }
    func freeBusy(matching query: CalendarEventQuery) throws -> [CalendarBusyWindow] {
        lastQuery = query
        return [CalendarBusyWindow(startAt: sampleEvent.startAt, endAt: sampleEvent.endAt, eventIDs: [sampleEvent.id])]
    }
    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    func create(_ request: CalendarEventCreateRequest) throws -> CalendarEvent {
        createdRequest = request
        return sampleEvent
    }
    func update(
        _ identity: CalendarEventIdentity,
        with request: CalendarEventUpdateRequest,
        span: CalendarEventMutationSpan
    ) throws -> CalendarEvent {
        updatedIdentity = identity
        updatedRequest = request
        updatedSpan = span
        return sampleEvent
    }
    func delete(_ identity: CalendarEventIdentity, span: CalendarEventMutationSpan) throws {
        deletedIdentity = identity
        deletedSpan = span
    }
}

private func jsonData(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
}

private func responseJSON(_ response: StetMCPHTTPResult) throws -> [String: Any] {
    let body = try #require(response.body)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}
