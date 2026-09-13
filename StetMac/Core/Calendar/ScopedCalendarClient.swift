#if os(macOS)
    import Foundation

    @MainActor
    final class ScopedCalendarClient: CalendarWriteClient {
        private let client: any CalendarWriteClient
        private let selectionStore: SelectedCalendarStore

        init(client: any CalendarWriteClient, selectionStore: SelectedCalendarStore) {
            self.client = client
            self.selectionStore = selectionStore
        }

        func authorizationStatus() -> CalendarAuthorizationStatus {
            client.authorizationStatus()
        }

        func requestFullAccess() async throws -> Bool {
            try await client.requestFullAccess()
        }

        func calendars() throws -> [CalendarRecord] {
            let selected = selectionStore.load()
            return try client.calendars().filter { selected.contains($0.id) }
        }

        func defaultCalendarID() throws -> String? {
            guard let id = try client.defaultCalendarID(), selectionStore.load().contains(id) else { return nil }
            return id
        }

        func events(matching query: CalendarEventQuery) throws -> [CalendarEvent] {
            try client.events(matching: scoped(query))
        }

        func event(_ identity: CalendarEventIdentity) throws -> CalendarEvent {
            try requireSelected(identity.calendarID)
            return try client.event(identity)
        }

        func freeBusy(matching query: CalendarEventQuery) throws -> [CalendarBusyWindow] {
            try client.freeBusy(matching: scoped(query))
        }

        func changes() -> AsyncStream<Void> {
            client.changes()
        }

        func create(_ request: CalendarEventCreateRequest) throws -> CalendarEvent {
            try requireSelected(request.calendarID)
            return try client.create(request)
        }

        func update(
            _ identity: CalendarEventIdentity,
            with request: CalendarEventUpdateRequest,
            span: CalendarEventMutationSpan
        ) throws -> CalendarEvent {
            try requireSelected(identity.calendarID)
            if let calendarID = request.calendarID { try requireSelected(calendarID) }
            return try client.update(identity, with: request, span: span)
        }

        func delete(_ identity: CalendarEventIdentity, span: CalendarEventMutationSpan) throws {
            try requireSelected(identity.calendarID)
            try client.delete(identity, span: span)
        }

        private func scoped(_ query: CalendarEventQuery) throws -> CalendarEventQuery {
            let selected = selectionStore.load()
            let requested = query.calendarIDs.isEmpty ? selected : query.calendarIDs
            guard requested.isSubset(of: selected) else {
                let disallowed = requested.subtracting(selected).sorted().joined(separator: ", ")
                throw CalendarClientError.calendarNotAllowed(disallowed)
            }
            return CalendarEventQuery(
                startAt: query.startAt,
                endAt: query.endAt,
                calendarIDs: requested
            )
        }

        private func requireSelected(_ calendarID: String) throws {
            guard selectionStore.load().contains(calendarID) else {
                throw CalendarClientError.calendarNotAllowed(calendarID)
            }
        }
    }
#endif
