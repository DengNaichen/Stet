import ActivityKit
import SwiftUI
import UIKit

struct RewriteSettingsView: View {
    @ObservedObject var viewModel: RewriteSettingsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(
        MobileDictationVisualTheme.mobileStorageKey,
        store: MobileDictationVisualTheme.mobileDefaults
    ) private var themeRawValue = MobileDictationVisualTheme.egg.rawValue

    @State private var areLiveActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled

    var body: some View {
        NavigationStack {
            List {
                preferencesSection
                systemSection
            }
            .listStyle(.insetGrouped)
            .linearInlineHeader("Settings")
            .onAppear {
                viewModel.refreshSyncedAPIKey()
                refreshLiveActivityAuthorization()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshLiveActivityAuthorization()
                }
            }
            .task {
                await viewModel.refreshSpeechAssetStatus()
            }
        }
    }

    private var preferencesSection: some View {
        Section {
            NavigationLink {
                SpeechSettingsDetailView(viewModel: viewModel)
            } label: {
                settingsHubRow("Speech", systemImage: "waveform") {
                    speechSummaryView
                }
            }

            NavigationLink {
                MicrophoneSettingsDetailView(viewModel: viewModel)
            } label: {
                settingsHubRow("Microphone", systemImage: "mic") {
                    Text(viewModel.microphoneKeepAliveDuration.shortLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                AIRewriteSettingsDetailView(viewModel: viewModel)
            } label: {
                settingsHubRow("AI Rewrite", systemImage: "sparkles") {
                    Text(viewModel.rewriteSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            NavigationLink {
                AppearanceSettingsDetailView(themeRawValue: $themeRawValue)
            } label: {
                settingsHubRow("Appearance", systemImage: "circle.lefthalf.filled") {
                    HStack(spacing: 7) {
                        ThemeOrbSwatch(theme: selectedTheme, size: 18)
                        Text(selectedTheme.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var systemSection: some View {
        Section("System") {
            Button {
                openSystemSettings()
            } label: {
                settingsHubRow("Live Activity", systemImage: "platter.filled.top.iphone") {
                    if areLiveActivitiesEnabled {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("On")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Text("Off")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            settingsHubRow("Version", systemImage: "info.circle") {
                Text(appVersionText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var speechSummaryView: some View {
        HStack(spacing: 6) {
            Text(viewModel.selectedLanguage.shortLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            switch viewModel.speechAssetStatus {
            case .installed:
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            case .downloading, .checking:
                ProgressView()
                    .controlSize(.mini)
            case .available, .failed:
                Circle()
                    .fill(MobileLinearPalette.accentAmber)
                    .frame(width: 6, height: 6)
            case .unsupported:
                EmptyView()
            }
        }
    }

    private func settingsHubRow<Trailing: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            SettingsRowLabel(title, systemImage: systemImage)
            Spacer(minLength: 8)
            trailing()
        }
    }

    private func refreshLiveActivityAuthorization() {
        areLiveActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var selectedTheme: MobileDictationVisualTheme {
        MobileDictationVisualTheme(rawValue: themeRawValue) ?? .egg
    }

    private var appVersionText: String {
        let shortVersion =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return shortVersion ?? "0.8.0"
    }
}

struct SettingsRowLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
            Text(title)
                .foregroundStyle(.primary)
        }
    }
}
