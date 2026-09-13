#if os(macOS)
    import SwiftUI

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

    struct MacCalendarMeetingSettingsView: View {
        let appModel: any MacCalendarSettingsAppModeling

        @State private var calendars: [CalendarRecord] = []
        @State private var selectedIDs: Set<String> = []
        @State private var isEnabled = false
        @State private var isChanging = false
        @State private var errorMessage: String?

        var body: some View {
            Group {
                Section {
                    Toggle(
                        "Calendar Meetings",
                        isOn: Binding(
                            get: { isEnabled },
                            set: { enabled in
                                isEnabled = enabled
                                isChanging = true
                                Task {
                                    await appModel.setCalendarMeetingsEnabled(enabled)
                                    isEnabled = appModel.isCalendarMeetingsEnabled
                                    isChanging = false
                                    reload()
                                }
                            }
                        )
                    )
                    .disabled(isChanging)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                        Text(statusText)
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Sync selected calendars and remind you five minutes before meetings.")
                }

                if appModel.calendarAuthorizationStatus == .fullAccess,
                    appModel.isCalendarMeetingsEnabled
                {
                    Section {
                        if calendars.isEmpty {
                            Text("No calendars available")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(calendars) { calendar in
                                Toggle(
                                    calendar.title,
                                    isOn: Binding(
                                        get: { selectedIDs.contains(calendar.id) },
                                        set: { selected in update(calendar.id, selected: selected) }
                                    )
                                )
                            }
                        }
                    } header: {
                        Text("Calendars")
                    } footer: {
                        if let errorMessage {
                            Text(errorMessage)
                        } else {
                            Text("Only selected calendars are synced into Stet meetings and Calendar MCP tools.")
                        }
                    }
                }
            }
            .onAppear(perform: reload)
        }

        private var statusText: LocalizedStringKey {
            switch appModel.calendarSyncState {
            case .disabled:
                "Off"
            case .permissionRequired:
                "Calendar access required"
            case .idle:
                "Ready"
            case .syncing:
                "Syncing…"
            case .active:
                "Up to date"
            case .failed:
                "Sync failed"
            }
        }

        private var statusColor: Color {
            switch appModel.calendarSyncState {
            case .active:
                .green
            case .failed:
                .red
            case .permissionRequired:
                .orange
            case .syncing, .idle:
                .blue
            case .disabled:
                .secondary
            }
        }

        private func reload() {
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

        private func update(_ id: String, selected: Bool) {
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
