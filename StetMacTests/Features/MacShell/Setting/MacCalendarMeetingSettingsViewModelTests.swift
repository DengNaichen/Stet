#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Calendar settings presentation")
    struct MacCalendarMeetingSettingsViewModelTests {
        @Test func permissionControlsCalendarLoading() {
            let app = CalendarSettingsStub()
            let model = MacCalendarMeetingSettingsViewModel(appModel: app)
            model.reload()
            #expect(app.calendarReads == 0)
            #expect(model.calendars.isEmpty)

            app.calendarAuthorizationStatus = .fullAccess
            app.isCalendarMeetingsEnabled = true
            app.selectedCalendarIDs = ["work"]
            model.reload()
            #expect(app.calendarReads == 1)
            #expect(model.calendars == app.records)
            #expect(model.selectedIDs == ["work"])
        }

        @Test func failedReloadKeepsLastListAndSuccessfulReloadClearsError() {
            let app = CalendarSettingsStub()
            app.calendarAuthorizationStatus = .fullAccess
            let model = MacCalendarMeetingSettingsViewModel(appModel: app)
            model.reload()
            app.failRead = true
            model.reload()
            #expect(model.calendars == app.records)
            #expect(model.errorMessage == "Calendar unavailable")
            app.failRead = false
            model.reload()
            #expect(model.errorMessage == nil)
        }

        @Test func enablingIsOptimisticThenReconcilesWithAuthorizationOutcome() async {
            let app = CalendarSettingsStub()
            let model = MacCalendarMeetingSettingsViewModel(appModel: app)
            model.setEnabled(true)
            #expect(model.isEnabled)
            #expect(model.isChanging)
            let finished = await TestSupport.eventuallyAsync {
                await MainActor.run { !model.isChanging }
            }
            #expect(finished)
            #expect(app.enabledRequests == [true])
            // A permission denial leaves the authoritative setting disabled.
            #expect(!model.isEnabled)
        }

        @Test func selectionWritesTheWholeUpdatedSet() async {
            let app = CalendarSettingsStub()
            app.selectedCalendarIDs = ["personal"]
            let model = MacCalendarMeetingSettingsViewModel(appModel: app)
            model.reload()
            model.update("work", selected: true)
            #expect(model.selectedIDs == ["personal", "work"])
            let inserted = await TestSupport.eventuallyAsync {
                await MainActor.run { app.selectedCalendarIDs == ["personal", "work"] }
            }
            #expect(inserted)
            model.update("personal", selected: false)
            let removed = await TestSupport.eventuallyAsync {
                await MainActor.run { app.selectedCalendarIDs == ["work"] }
            }
            #expect(removed)
        }
    }

    @MainActor
    private final class CalendarSettingsStub: MacCalendarSettingsAppModeling {
        var isCalendarMeetingsEnabled = false
        var calendarAuthorizationStatus: CalendarAuthorizationStatus = .denied
        var calendarSyncState: CalendarSyncState = .disabled
        var selectedCalendarIDs: Set<String> = []
        var enabledRequests: [Bool] = []
        var calendarReads = 0
        var failRead = false
        let records = [
            CalendarRecord(
                id: "work", title: "Work",
                source: CalendarSourceRecord(id: "local", title: "Local", type: .local),
                colorHex: nil, isEditable: true, isSubscribed: false)
        ]

        func availableCalendars() throws -> [CalendarRecord] {
            calendarReads += 1
            if failRead { throw LoadError.unavailable }
            return records
        }

        func setCalendarMeetingsEnabled(_ enabled: Bool) async {
            enabledRequests.append(enabled)
            isCalendarMeetingsEnabled = enabled && calendarAuthorizationStatus == .fullAccess
        }

        func setSelectedCalendarIDs(_ ids: Set<String>) async {
            selectedCalendarIDs = ids
        }

        private enum LoadError: LocalizedError {
            case unavailable
            var errorDescription: String? { "Calendar unavailable" }
        }
    }
#endif
