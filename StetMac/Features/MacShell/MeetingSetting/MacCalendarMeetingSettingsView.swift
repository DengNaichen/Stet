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
                LinearSectionGroup(
                    "Calendar",
                    footer: "Sync selected calendars and remind you five minutes before meetings."
                ) {
                    LinearSettingRow("Calendar Meetings") {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { viewModel.isEnabled },
                                set: { viewModel.setEnabled($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(MacUI.LinearBrand.accent)
                        .disabled(viewModel.isChanging)
                    }

                    LinearSettingRow("Sync Status") {
                        LinearBadge(text: statusTitle, tint: statusColor, showDot: true)
                    }
                }

                if showsCalendars {
                    LinearSectionGroup(
                        "Calendars",
                        footer: viewModel.errorMessage == nil
                            ? "Only selected calendars are synced into Stet meetings and Calendar MCP tools."
                            : nil
                    ) {
                        if viewModel.calendars.isEmpty {
                            Text("No calendars available")
                                .font(MacUI.LinearTypography.rowSubtitle)
                                .foregroundStyle(MacUI.Foreground.secondary)
                                .padding(.horizontal, MacUI.LinearMetrics.rowHorizontalPadding)
                                .padding(.vertical, 12)
                        } else {
                            ForEach(viewModel.calendars) { calendar in
                                LinearSettingRow(titleText: calendar.title) {
                                    Toggle(
                                        "",
                                        isOn: Binding(
                                            get: { viewModel.selectedIDs.contains(calendar.id) },
                                            set: { selected in viewModel.update(calendar.id, selected: selected) }
                                        )
                                    )
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .tint(MacUI.LinearBrand.accent)
                                }
                            }
                        }

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(MacUI.LinearTypography.rowSubtitle)
                                .foregroundStyle(MacUI.Foreground.error)
                                .padding(.horizontal, MacUI.LinearMetrics.rowHorizontalPadding)
                                .padding(.vertical, 9)
                        }
                    }
                }
            }
            .onAppear(perform: viewModel.reload)
        }

        private var statusTitle: String {
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
                MacUI.Foreground.success
            case .failed:
                MacUI.Foreground.error
            case .permissionRequired:
                MacUI.Foreground.warning
            case .syncing, .idle:
                MacUI.Foreground.secondaryColor
            case .disabled:
                MacUI.Foreground.secondaryColor
            }
        }
    }
#endif
