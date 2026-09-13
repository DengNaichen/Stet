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
    }

    extension CalendarReadClient {
        func defaultCalendarID() throws -> String? { nil }
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
