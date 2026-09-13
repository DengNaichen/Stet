#if os(macOS)
    import AppKit
    import Foundation

    nonisolated protocol CalendarMeetingSyncing: Sendable {
        func reconcileCalendarMeetings(
            windowStart: Date,
            windowEnd: Date,
            inputs: [ExpectedMeetingInput]
        ) async throws
    }

    nonisolated enum CalendarSyncState: Equatable, Sendable {
        case disabled
        case permissionRequired(CalendarAuthorizationStatus)
        case idle
        case syncing
        case active(Date)
        case failed(String)
    }

    @MainActor
    final class CalendarSyncController {
        private let client: any CalendarReadClient
        private let selectionStore: SelectedCalendarStore
        private let synchronizer: any CalendarMeetingSyncing
        private let mapper: CalendarMeetingMapper
        private let now: @Sendable () -> Date
        private let lookAhead: TimeInterval
        private let refreshInterval: TimeInterval
        private var observationTask: Task<Void, Never>?
        private var periodicTask: Task<Void, Never>?
        private var refreshTask: Task<Void, Error>?
        private var refreshPending = false
        private var generation = 0
        private var wakeObserver: NSObjectProtocol?
        private(set) var state: CalendarSyncState = .disabled
        var onStateChange: ((CalendarSyncState) -> Void)?

        init(
            client: any CalendarReadClient,
            selectionStore: SelectedCalendarStore,
            synchronizer: any CalendarMeetingSyncing,
            mapper: CalendarMeetingMapper = CalendarMeetingMapper(),
            lookAhead: TimeInterval = 14 * 24 * 60 * 60,
            refreshInterval: TimeInterval = 60 * 60,
            now: @escaping @Sendable () -> Date = Date.init
        ) {
            self.client = client
            self.selectionStore = selectionStore
            self.synchronizer = synchronizer
            self.mapper = mapper
            self.lookAhead = min(max(lookAhead, 1), CalendarEventQuery.maximumDuration)
            self.refreshInterval = max(refreshInterval, 60)
            self.now = now
        }

        deinit {
            observationTask?.cancel()
            periodicTask?.cancel()
            refreshTask?.cancel()
            refreshPending = false
            if let wakeObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            }
        }

        var authorizationStatus: CalendarAuthorizationStatus { client.authorizationStatus() }

        var selectedCalendarIDs: Set<String> { selectionStore.load() }

        func calendars() throws -> [CalendarRecord] {
            try client.calendars()
        }

        func requestAccess() async throws -> Bool {
            try await client.requestFullAccess()
        }

        func setSelectedCalendarIDs(_ ids: Set<String>) async {
            generation += 1
            let selectionGeneration = generation
            selectionStore.save(ids)
            let task = refreshTask
            task?.cancel()
            try? await task?.value
            guard selectionGeneration == generation else { return }
            refreshTask = nil
            if state != .disabled { try? await refresh() }
        }

        func start() async {
            generation += 1
            guard client.authorizationStatus() == .fullAccess else {
                await clearCalendarMeetings()
                updateState(.permissionRequired(client.authorizationStatus()))
                return
            }
            updateState(.idle)
            startObservingChanges()
            startPeriodicRefresh()
            startObservingWake()
            try? await refresh()
        }

        func stopAndClear() async {
            let task = refreshTask
            stop()
            let stopGeneration = generation
            try? await task?.value
            guard stopGeneration == generation else { return }
            let start = Calendar.current.startOfDay(for: now())
            try? await synchronizer.reconcileCalendarMeetings(
                windowStart: start,
                windowEnd: start.addingTimeInterval(lookAhead),
                inputs: []
            )
            updateState(.disabled)
        }

        func stop() {
            generation += 1
            stopObservingChanges()
            periodicTask?.cancel()
            periodicTask = nil
            refreshTask?.cancel()
            refreshTask = nil
            refreshPending = false
            if let wakeObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
                self.wakeObserver = nil
            }
        }

        func refresh() async throws {
            if let refreshTask {
                refreshPending = true
                try await refreshTask.value
                return
            }
            repeat {
                refreshPending = false
                let task = Task { try await performRefresh() }
                refreshTask = task
                do {
                    try await task.value
                } catch {
                    refreshTask = nil
                    throw error
                }
                refreshTask = nil
            } while refreshPending
        }

        private func performRefresh() async throws {
            let refreshGeneration = generation
            updateState(.syncing)
            do {
                let currentTime = now()
                let start = Calendar.current.startOfDay(for: currentTime)
                let end = currentTime.addingTimeInterval(lookAhead)
                guard client.authorizationStatus() == .fullAccess else {
                    throw CalendarClientError.accessNotGranted(client.authorizationStatus())
                }
                let selectedIDs = selectionStore.load()
                let events = try client.events(
                    matching: CalendarEventQuery(startAt: start, endAt: end, calendarIDs: selectedIDs)
                )
                try Task.checkCancellation()
                guard refreshGeneration == generation else { throw CancellationError() }
                try await synchronizer.reconcileCalendarMeetings(
                    windowStart: start,
                    windowEnd: end,
                    inputs: mapper.map(events)
                )
                try Task.checkCancellation()
                guard refreshGeneration == generation else { throw CancellationError() }
                updateState(.active(now()))
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as CalendarClientError {
                if case .accessNotGranted(let status) = error {
                    await clearCalendarMeetings()
                    updateState(.permissionRequired(status))
                } else {
                    updateState(.failed(error.localizedDescription))
                }
                throw error
            } catch {
                updateState(.failed(error.localizedDescription))
                throw error
            }
        }

        private func clearCalendarMeetings() async {
            let start = Calendar.current.startOfDay(for: now())
            try? await synchronizer.reconcileCalendarMeetings(
                windowStart: start,
                windowEnd: start.addingTimeInterval(lookAhead),
                inputs: []
            )
        }

        func startObservingChanges() {
            guard observationTask == nil else { return }
            let changes = client.changes()
            observationTask = Task { [weak self] in
                for await _ in changes {
                    guard !Task.isCancelled else { return }
                    try? await self?.refresh()
                }
            }
        }

        func stopObservingChanges() {
            observationTask?.cancel()
            observationTask = nil
        }

        private func startPeriodicRefresh() {
            guard periodicTask == nil else { return }
            let interval = refreshInterval
            periodicTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval))
                    guard !Task.isCancelled else { return }
                    try? await self?.refresh()
                }
            }
        }

        private func startObservingWake() {
            guard wakeObserver == nil else { return }
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in try? await self?.refresh() }
            }
        }

        private func updateState(_ state: CalendarSyncState) {
            guard self.state != state else { return }
            self.state = state
            onStateChange?(state)
        }
    }

#endif
