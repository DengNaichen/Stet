#if os(macOS)
    import Combine
    import Foundation

    /// Presentation facade over the app's meeting and passive-listening state.
    @MainActor
    final class MacMeetingViewModel: ObservableObject, MacMeetingCoordinating {
        private let coordinator: any MacMeetingCoordinating
        private var cancellables = Set<AnyCancellable>()

        init(coordinator: any MacMeetingCoordinating) {
            self.coordinator = coordinator
            coordinator.updates
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }

        var updates: AnyPublisher<Void, Never> { objectWillChange.eraseToAnyPublisher() }

        var meetingRecordingPhase: MacMeetingRecordingPhase { coordinator.meetingRecordingPhase }
        var isMeetingBusy: Bool { coordinator.isMeetingBusy }
        var meetingStatusText: String { coordinator.meetingStatusText }
        var meetingMenuSymbolName: String { coordinator.meetingMenuSymbolName }
        var meetingToggleTitle: String { coordinator.meetingToggleTitle }
        var canToggleMeetingRecording: Bool { coordinator.canToggleMeetingRecording }
        var passiveListeningStatusText: String { coordinator.passiveListeningStatusText }
        var isPassiveMicrophoneActive: Bool { coordinator.isPassiveMicrophoneActive }

        func toggleMeetingRecording() {
            coordinator.toggleMeetingRecording()
        }

        var isCalendarMeetingsEnabled: Bool { coordinator.isCalendarMeetingsEnabled }
        var calendarAuthorizationStatus: CalendarAuthorizationStatus { coordinator.calendarAuthorizationStatus }
        var calendarSyncState: CalendarSyncState { coordinator.calendarSyncState }
        var selectedCalendarIDs: Set<String> { coordinator.selectedCalendarIDs }

        func availableCalendars() throws -> [CalendarRecord] {
            try coordinator.availableCalendars()
        }

        func setCalendarMeetingsEnabled(_ enabled: Bool) async {
            await coordinator.setCalendarMeetingsEnabled(enabled)
        }

        func setSelectedCalendarIDs(_ ids: Set<String>) async {
            await coordinator.setSelectedCalendarIDs(ids)
        }
    }
#endif
