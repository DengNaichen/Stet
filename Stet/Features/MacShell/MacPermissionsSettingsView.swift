#if os(macOS)
import SwiftUI

struct MacPermissionsSettingsView: View {
    @EnvironmentObject private var appModel: MacAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard(
                title: "Core Permissions",
                description: "Stet uses separate permissions for capture, hotkeys, and writing text back into other apps."
            ) {
                permissionRow(
                    title: "Microphone",
                    detail: "Required to capture audio for dictation.",
                    statusText: appModel.microphoneAccessStatusText,
                    tint: appModel.microphoneAccessNeedsAttention ? .orange : .green
                ) {
                    Button("Open Settings") {
                        appModel.openMicrophoneSettings()
                    }
                }

                permissionRow(
                    title: "Speech Recognition",
                    detail: "The current on-device speech path does not require the legacy Speech Recognition permission.",
                    statusText: appModel.speechRecognitionStatusText,
                    tint: .gray
                ) {
                    EmptyView()
                }

                permissionRow(
                    title: "Text Injection",
                    detail: "Accessibility helps read selected text directly. Input injection is used to paste captured text back into other apps automatically.",
                    statusText: appModel.autoPasteStatusText,
                    tint: appModel.autoPasteAccessNeedsAttention ? .orange : .green
                ) {
                    Button("Request Access") {
                        appModel.requestAutoPasteAccess()
                    }

                    Button("Open Settings") {
                        appModel.openAccessibilitySettings()
                    }
                }

                permissionRow(
                    title: "Input Monitoring",
                    detail: "Required for modifier-only shortcuts like fn and for the event-tap hotkey backend.",
                    statusText: appModel.inputMonitoringStatusText,
                    tint: appModel.inputMonitoringNeedsAttention ? .orange : .green
                ) {
                    Button("Request Access") {
                        appModel.requestInputMonitoringAccess()
                    }

                    Button("Open Settings") {
                        appModel.openInputMonitoringSettings()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(
        title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)

                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    @ViewBuilder
    private func permissionRow<Actions: View>(
        title: String,
        detail: String,
        statusText: String,
        tint: Color,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusBadge(statusText, tint: tint)
            actions()
        }
        .padding(.vertical, 2)
    }

    private func statusBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            )
    }
}
#endif
