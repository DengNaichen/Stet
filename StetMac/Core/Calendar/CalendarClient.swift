#if os(macOS)
    import Foundation

    @MainActor
    protocol CalendarReadClient: Sendable {
        func authorizationStatus() -> CalendarAuthorizationStatus
        func requestFullAccess() async throws -> Bool
        func calendars() throws -> [CalendarRecord]
        func defaultCalendarID() throws -> String?
        func events(matching query: CalendarEventQuery) throws -> [CalendarEvent]
        func event(_ identity: CalendarEventIdentity) throws -> CalendarEvent
        func freeBusy(matching query: CalendarEventQuery) throws -> [CalendarBusyWindow]
        func changes() -> AsyncStream<Void>
        // Query entry points allow live clients to keep EventKit I/O off the UI actor.
        nonisolated func queryCalendars() async throws -> [CalendarRecord]
        nonisolated func queryEvents(matching query: CalendarEventQuery) async throws -> [CalendarEvent]
        nonisolated func queryEvent(_ identity: CalendarEventIdentity) async throws -> CalendarEvent
    }

    extension CalendarReadClient {
        func defaultCalendarID() throws -> String? { nil }

        nonisolated func queryCalendars() async throws -> [CalendarRecord] { try await calendars() }
        nonisolated func queryEvents(matching query: CalendarEventQuery) async throws -> [CalendarEvent] {
            try await events(matching: query)
        }
        nonisolated func queryEvent(_ identity: CalendarEventIdentity) async throws -> CalendarEvent {
            try await event(identity)
        }
    }

    @MainActor
    protocol CalendarWriteClient: CalendarReadClient {
        func create(_ request: CalendarEventCreateRequest) throws -> CalendarEvent
        func update(
            _ identity: CalendarEventIdentity,
            with request: CalendarEventUpdateRequest,
            span: CalendarEventMutationSpan
        ) throws -> CalendarEvent
        func delete(_ identity: CalendarEventIdentity, span: CalendarEventMutationSpan) throws
    }
#endif
