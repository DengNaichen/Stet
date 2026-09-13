#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Scoped Calendar Client")
    struct ScopedCalendarClientTests {
        @Test func exposesOnlySelectedCalendarsAndScopesDefaultQueries() throws {
            let client = ScopedCalendarFake()
            let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
            let selection = SelectedCalendarStore(defaults: defaults, key: "selected")
            selection.save(["work"])
            let scoped = ScopedCalendarClient(client: client, selectionStore: selection)

            #expect(try scoped.calendars().map(\.id) == ["work"])
            _ = try scoped.events(
                matching: CalendarEventQuery(
                    startAt: Date(timeIntervalSince1970: 1),
                    endAt: Date(timeIntervalSince1970: 2),
                    calendarIDs: []
                )
            )
            #expect(client.lastQuery?.calendarIDs == ["work"])
        }

        @Test func rejectsReadAndWriteOutsideSelectedCalendars() throws {
            let client = ScopedCalendarFake()
            let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
            let selection = SelectedCalendarStore(defaults: defaults, key: "selected")
            selection.save(["work"])
            let scoped = ScopedCalendarClient(client: client, selectionStore: selection)
            let query = CalendarEventQuery(
                startAt: Date(timeIntervalSince1970: 1),
                endAt: Date(timeIntervalSince1970: 2),
                calendarIDs: ["personal"]
            )

            #expect(throws: CalendarClientError.calendarNotAllowed("personal")) {
                try scoped.events(matching: query)
            }
            #expect(throws: CalendarClientError.calendarNotAllowed("personal")) {
                try scoped.create(
                    CalendarEventCreateRequest(
                        calendarID: "personal",
                        title: "Private",
                        startAt: query.startAt,
                        endAt: query.endAt
                    )
                )
            }
        }
    }

    @MainActor
    private final class ScopedCalendarFake: CalendarWriteClient {
        var lastQuery: CalendarEventQuery?

        func authorizationStatus() -> CalendarAuthorizationStatus { .fullAccess }
        func requestFullAccess() async throws -> Bool { true }
        func calendars() throws -> [CalendarRecord] {
            [calendar(id: "work"), calendar(id: "personal")]
        }
        func events(matching query: CalendarEventQuery) throws -> [CalendarEvent] {
            lastQuery = query
            return []
        }
        func event(_ identity: CalendarEventIdentity) throws -> CalendarEvent {
            throw CalendarClientError.eventNotFound(identity)
        }
        func freeBusy(matching query: CalendarEventQuery) throws -> [CalendarBusyWindow] {
            lastQuery = query
            return []
        }
        func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
        func create(_ request: CalendarEventCreateRequest) throws -> CalendarEvent {
            throw CalendarClientError.calendarNotFound(request.calendarID)
        }
        func update(
            _ identity: CalendarEventIdentity,
            with request: CalendarEventUpdateRequest,
            span: CalendarEventMutationSpan
        ) throws -> CalendarEvent {
            throw CalendarClientError.eventNotFound(identity)
        }
        func delete(_ identity: CalendarEventIdentity, span: CalendarEventMutationSpan) throws {}

        private func calendar(id: String) -> CalendarRecord {
            CalendarRecord(
                id: id,
                title: id.capitalized,
                source: CalendarSourceRecord(id: "source", title: "Source", type: .calDAV),
                colorHex: nil,
                isEditable: true,
                isSubscribed: false
            )
        }
    }
#endif
