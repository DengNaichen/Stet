#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Calendar Sync Controller")
    struct CalendarSyncControllerTests {
        @Test func refreshFetchesOnlySelectedCalendarsAndReconcilesMappedEvents() async throws {
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            let client = FakeCalendarClient(events: [makeSyncEvent(start: now.addingTimeInterval(60))])
            let synchronizer = CalendarSynchronizerSpy()
            let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
            let selection = SelectedCalendarStore(defaults: defaults, key: "selected")
            selection.save(["calendar-1"])
            let controller = CalendarSyncController(
                client: client,
                selectionStore: selection,
                synchronizer: synchronizer,
                lookAhead: 3_600,
                now: { now }
            )

            try await controller.refresh()

            #expect(client.lastQuery?.calendarIDs == ["calendar-1"])
            #expect(client.lastQuery?.startAt == Calendar.current.startOfDay(for: now))
            #expect(client.lastQuery?.endAt == now.addingTimeInterval(3_600))
            #expect(await synchronizer.inputs.count == 1)
        }

        @Test func refreshWithNoSelectionStillReconcilesEmptyWindow() async throws {
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            let client = FakeCalendarClient(events: [])
            let synchronizer = CalendarSynchronizerSpy()
            let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
            let controller = CalendarSyncController(
                client: client,
                selectionStore: SelectedCalendarStore(defaults: defaults, key: "selected"),
                synchronizer: synchronizer,
                now: { now }
            )

            try await controller.refresh()

            #expect(client.lastQuery?.calendarIDs.isEmpty == true)
            #expect(await synchronizer.inputs.isEmpty)
            #expect(await synchronizer.callCount == 1)
        }

        @Test(arguments: [
            CalendarAuthorizationStatus.notDetermined,
            .writeOnly,
            .denied,
            .restricted,
        ])
        func refreshRejectsMissingFullAccess(_ status: CalendarAuthorizationStatus) async {
            let client = FakeCalendarClient(status: status)
            let synchronizer = CalendarSynchronizerSpy()
            let controller = CalendarSyncController(
                client: client,
                selectionStore: SelectedCalendarStore(),
                synchronizer: synchronizer
            )

            await #expect(throws: CalendarClientError.accessNotGranted(status)) {
                try await controller.refresh()
            }
            #expect(await synchronizer.callCount == 1)
            #expect(await synchronizer.inputs.isEmpty)
        }

        @Test func removedEventsReconcileAsAnEmptySelectedWindow() async throws {
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            let client = FakeCalendarClient(events: [makeSyncEvent(start: now.addingTimeInterval(60))])
            let synchronizer = CalendarSynchronizerSpy()
            let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
            let selection = SelectedCalendarStore(defaults: defaults, key: "selected")
            selection.save(["calendar-1"])
            let controller = CalendarSyncController(
                client: client,
                selectionStore: selection,
                synchronizer: synchronizer,
                now: { now }
            )

            try await controller.refresh()
            client.resultEvents = []
            try await controller.refresh()

            #expect(await synchronizer.callCount == 2)
            #expect(await synchronizer.inputs.isEmpty)
        }

        @Test func cancelledRefreshCannotClearTheReplacementTask() async throws {
            let client = FakeCalendarClient()
            let synchronizer = SuspendedCalendarSynchronizer()
            let controller = CalendarSyncController(
                client: client,
                selectionStore: SelectedCalendarStore(
                    defaults: try #require(UserDefaults(suiteName: UUID().uuidString)), key: "selected"
                ),
                synchronizer: synchronizer
            )
            let first = Task { try? await controller.refresh() }
            #expect(await TestSupport.eventuallyAsync { await synchronizer.callCount == 1 })
            controller.stop()
            let second = Task { try? await controller.refresh() }
            #expect(await TestSupport.eventuallyAsync { await synchronizer.callCount == 2 })
            await synchronizer.release(1)
            await first.value

            let third = Task { try? await controller.refresh() }
            // Give the third caller a chance to join the replacement refresh.
            for _ in 0..<20 { await Task.yield() }
            #expect(await synchronizer.callCount == 2)
            await synchronizer.releaseAll()
            await second.value
            await third.value
            controller.stop()
        }

        @Test func eventStoreChangeTriggersRefresh() async throws {
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            let client = FakeCalendarClient(events: [makeSyncEvent(start: now.addingTimeInterval(60))])
            let synchronizer = CalendarSynchronizerSpy()
            let controller = CalendarSyncController(
                client: client,
                selectionStore: SelectedCalendarStore(
                    defaults: try #require(UserDefaults(suiteName: UUID().uuidString)),
                    key: "selected"
                ),
                synchronizer: synchronizer,
                now: { now }
            )

            controller.startObservingChanges()
            client.sendChange()
            for _ in 0..<20 where await synchronizer.callCount == 0 { await Task.yield() }
            controller.stopObservingChanges()

            #expect(await synchronizer.callCount == 1)
        }
    }

    @MainActor
    private final class FakeCalendarClient: CalendarReadClient {
        let status: CalendarAuthorizationStatus
        var resultEvents: [CalendarEvent]
        var lastQuery: CalendarEventQuery?
        private var changeContinuation: AsyncStream<Void>.Continuation?

        init(status: CalendarAuthorizationStatus = .fullAccess, events: [CalendarEvent] = []) {
            self.status = status
            self.resultEvents = events
        }

        func authorizationStatus() -> CalendarAuthorizationStatus { status }
        func requestFullAccess() async throws -> Bool { status == .fullAccess }
        func calendars() throws -> [CalendarRecord] { [] }
        func events(matching query: CalendarEventQuery) throws -> [CalendarEvent] {
            lastQuery = query
            return resultEvents
        }
        func event(_ identity: CalendarEventIdentity) throws -> CalendarEvent {
            guard let event = resultEvents.first(where: { $0.identity == identity }) else {
                throw CalendarClientError.eventNotFound(identity)
            }
            return event
        }
        func freeBusy(matching query: CalendarEventQuery) throws -> [CalendarBusyWindow] { [] }
        func changes() -> AsyncStream<Void> {
            AsyncStream { changeContinuation = $0 }
        }

        func sendChange() {
            changeContinuation?.yield()
        }
    }

    private actor SuspendedCalendarSynchronizer: CalendarMeetingSyncing {
        private(set) var callCount = 0
        private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
        private var immediate = false

        func reconcileCalendarMeetings(
            windowStart: Date, windowEnd: Date, inputs: [ExpectedMeetingInput]
        ) async throws {
            callCount += 1
            let call = callCount
            if !immediate { await withCheckedContinuation { continuations[call] = $0 } }
            try Task.checkCancellation()
        }

        func release(_ call: Int) { continuations.removeValue(forKey: call)?.resume() }
        func releaseAll() {
            immediate = true
            let pending = continuations.values
            continuations.removeAll()
            for continuation in pending { continuation.resume() }
        }
    }

    private actor CalendarSynchronizerSpy: CalendarMeetingSyncing {
        var callCount = 0
        var inputs: [ExpectedMeetingInput] = []

        func reconcileCalendarMeetings(
            windowStart: Date,
            windowEnd: Date,
            inputs: [ExpectedMeetingInput]
        ) async throws {
            callCount += 1
            self.inputs = inputs
        }
    }

    private func makeSyncEvent(start: Date) -> CalendarEvent {
        CalendarEvent(
            identity: CalendarEventIdentity(
                eventID: "event-1",
                calendarID: "calendar-1",
                sourceID: "source-1",
                occurrence: nil
            ),
            title: "Sync",
            startAt: start,
            endAt: start.addingTimeInterval(1_800),
            isAllDay: false,
            status: .confirmed,
            availability: .busy,
            location: nil,
            url: nil,
            notes: nil,
            modifiedAt: nil,
            organizer: nil,
            attendees: []
        )
    }
#endif
