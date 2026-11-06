#if os(macOS)
    import SwiftUI

    struct MacCalendarMeetingSettingsView: View {
        // Live status comes from the parent; the model owns only editing and loading.
        private let syncState: CalendarSyncState
        private let showsCalendars: Bool
        @StateObject private var viewModel: MacCalendarMeetingSettingsViewModel

        init(appModel: any MacCalendarSettingsAppModeling) {
            syncState = appModel.calendarSyncState
            showsCalendars = appModel.calendarAuthorizationStatus == .fullAccess && appModel.isCalendarMeetingsEnabled
            _viewModel = StateObject(wrappedValue: MacCalendarMeetingSettingsViewModel(appModel: appModel))
        }

        var body: some View {
            Group {
                Section {
                    Toggle(
                        "Calendar Meetings",
                        isOn: Binding(
                            get: { viewModel.isEnabled },
                            set: { viewModel.setEnabled($0) }
                        )
                    )
                    .disabled(viewModel.isChanging)

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

                if showsCalendars {
                    Section {
                        if viewModel.calendars.isEmpty {
                            Text("No calendars available")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.calendars) { calendar in
                                Toggle(
                                    calendar.title,
                                    isOn: Binding(
                                        get: { viewModel.selectedIDs.contains(calendar.id) },
                                        set: { selected in viewModel.update(calendar.id, selected: selected) }
                                    )
                                )
                            }
                        }
                    } header: {
                        Text("Calendars")
                    } footer: {
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                        } else {
                            Text("Only selected calendars are synced into Stet meetings and Calendar MCP tools.")
                        }
                    }
                }
            }
            .onAppear(perform: viewModel.reload)
        }

        private var statusText: LocalizedStringKey {
            switch syncState {
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
            switch syncState {
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

    }
#endif
