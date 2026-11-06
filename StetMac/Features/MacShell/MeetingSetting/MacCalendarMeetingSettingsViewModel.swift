#if os(macOS)
    import Combine
    import Foundation

    @MainActor
    protocol MacCalendarSettingsAppModeling: AnyObject {
        var isCalendarMeetingsEnabled: Bool { get }
        var calendarAuthorizationStatus: CalendarAuthorizationStatus { get }
        var calendarSyncState: CalendarSyncState { get }
        var selectedCalendarIDs: Set<String> { get }
        func availableCalendars() throws -> [CalendarRecord]
        func setCalendarMeetingsEnabled(_ enabled: Bool) async
        func setSelectedCalendarIDs(_ ids: Set<String>) async
    }

    /// Owns the editable calendar settings snapshot and its asynchronous mutations.
    @MainActor
    final class MacCalendarMeetingSettingsViewModel: ObservableObject {
        @Published private(set) var calendars: [CalendarRecord] = []
        @Published private(set) var selectedIDs: Set<String> = []
        @Published private(set) var isEnabled = false
        @Published private(set) var isChanging = false
        @Published private(set) var errorMessage: String?

        private let appModel: any MacCalendarSettingsAppModeling

        init(appModel: any MacCalendarSettingsAppModeling) {
            self.appModel = appModel
        }

        func setEnabled(_ enabled: Bool) {
            isEnabled = enabled
            isChanging = true
            Task {
                await appModel.setCalendarMeetingsEnabled(enabled)
                isEnabled = appModel.isCalendarMeetingsEnabled
                isChanging = false
                reload()
            }
        }

        func reload() {
            isEnabled = appModel.isCalendarMeetingsEnabled
            selectedIDs = appModel.selectedCalendarIDs
            guard appModel.calendarAuthorizationStatus == .fullAccess else {
                calendars = []
                return
            }
            do {
                calendars = try appModel.availableCalendars()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        func update(_ id: String, selected: Bool) {
            if selected {
                selectedIDs.insert(id)
            } else {
                selectedIDs.remove(id)
            }
            let ids = selectedIDs
            Task { await appModel.setSelectedCalendarIDs(ids) }
        }
    }
#endif
