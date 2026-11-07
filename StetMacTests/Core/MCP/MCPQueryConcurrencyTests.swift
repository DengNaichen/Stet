#if os(macOS)
    import Foundation
    import MCP
    import Testing

    @testable import Stet

    @MainActor
    @Suite("MCP Query Concurrency")
    struct MCPQueryConcurrencyTests {
        @Test func meetingQueriesLeaveTheMainActorEvenWhenCalledFromUI() async {
            let tools = MCPRecordingTools(catalog: ThreadCheckingCatalog())
            let result = await tools.call(.init(name: MCPRecordingTools.listMeetingsToolName))
            #expect(result.isError != true)
        }

        @Test func calendarQueriesUseTheAsyncReadBoundary() async {
            let tools = MCPCalendarTools(readClient: QueryOnlyCalendarClient())
            let result = await tools.call(.init(name: MCPCalendarTools.listCalendarsToolName))
            #expect(result.isError != true)
        }
    }

    private nonisolated struct ThreadCheckingCatalog: MCPMeetingServing {
        func listMeetings(limit: Int) throws -> MCPMeetingListOutput {
            #expect(!Thread.isMainThread)
            return MCPMeetingListOutput(meetings: [])
        }
        func listUnorganizedMeetings(limit: Int) throws -> MCPMeetingListOutput { try listMeetings(limit: limit) }
        func meetingTranscript(meetingID: String?) throws -> MCPMeetingTranscriptOutput { throw TestError.expected }
    }

    @MainActor
    private final class QueryOnlyCalendarClient: CalendarReadClient {
        func authorizationStatus() -> CalendarAuthorizationStatus { .fullAccess }
        func requestFullAccess() async throws -> Bool { true }
        func calendars() throws -> [CalendarRecord] { throw TestError.expected }
        func events(matching query: CalendarEventQuery) throws -> [CalendarEvent] { throw TestError.expected }
        func event(_ identity: CalendarEventIdentity) throws -> CalendarEvent { throw TestError.expected }
        func freeBusy(matching query: CalendarEventQuery) throws -> [CalendarBusyWindow] { [] }
        func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
        nonisolated func queryCalendars() async throws -> [CalendarRecord] { [] }
    }
#endif
