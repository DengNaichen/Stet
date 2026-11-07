#if os(macOS)
    import Combine
    import Foundation
    import Observation

    /// Presentation facade over the app's meeting state.
    @MainActor
    @Observable
    final class MacMeetingViewModel: MacCalendarSettingsAppModeling {
        private let coordinator: any MacMeetingCoordinating
        private var snapshot: MacMeetingSnapshot
        @ObservationIgnored private var cancellable: AnyCancellable?

        init(coordinator: any MacMeetingCoordinating) {
            self.coordinator = coordinator
            snapshot = coordinator.meetingSnapshot
            cancellable = coordinator.meetingSnapshots.sink { [weak self] in
                self?.snapshot = $0
            }
        }

        var meetingSpeakerSettings: MeetingSpeakerSettings { coordinator.meetingSpeakerSettings }

        var meetingRecordingPhase: MacMeetingRecordingPhase { snapshot.meetingRecordingPhase }
        var isMeetingBusy: Bool { snapshot.isMeetingBusy }
        var meetingStatusText: String { snapshot.meetingStatusText }
        var meetingMenuSymbolName: String { snapshot.meetingMenuSymbolName }
        var meetingToggleTitle: String { snapshot.meetingToggleTitle }
        var canToggleMeetingRecording: Bool { snapshot.canToggleMeetingRecording }

        func toggleMeetingRecording() {
            coordinator.toggleMeetingRecording()
        }

        var isCalendarMeetingsEnabled: Bool { snapshot.isCalendarMeetingsEnabled }
        var calendarAuthorizationStatus: CalendarAuthorizationStatus { snapshot.calendarAuthorizationStatus }
        var calendarSyncState: CalendarSyncState { snapshot.calendarSyncState }
        var selectedCalendarIDs: Set<String> { snapshot.selectedCalendarIDs }

        func availableCalendars() throws -> [CalendarRecord] {
            try coordinator.availableCalendars()
        }

        func setCalendarMeetingsEnabled(_ enabled: Bool) async {
            await coordinator.setCalendarMeetingsEnabled(enabled)
            snapshot = coordinator.meetingSnapshot
        }

        func setSelectedCalendarIDs(_ ids: Set<String>) async {
            await coordinator.setSelectedCalendarIDs(ids)
            snapshot = coordinator.meetingSnapshot
        }
    }
#endif
