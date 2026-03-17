#if os(macOS)
import SwiftUI

struct MacPermissionsSettingsView: View {
    @EnvironmentObject private var appModel: MacAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard(
                title: "Core Permissions",
            ) {
                permissionRow(
                    title: "Microphone",
                    statusText: appModel.microphoneAccessStatusText,
                    tint: appModel.microphoneAccessNeedsAttention ? .orange : .green
                ) {
                    Button("Open Settings") {
                        appModel.openMicrophoneSettings()
                    }
                }
                permissionRow(
                    title: "Text Injection",
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
        statusText: String,
        tint: Color,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
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
