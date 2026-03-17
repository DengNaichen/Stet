#if os(macOS)
import AppKit
import SwiftUI

struct MacPermissionsSettingsView: View {
    @EnvironmentObject private var appModel: MacAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MacSettingsCard(
                title: "Core Permissions",
            ) {
                permissionRow(
                    title: "Microphone",
                    statusText: appModel.microphoneAccessStatusText,
                    tint: appModel.microphoneAccessNeedsAttention ? .orange : .green
                ) {
                    Button(appModel.microphonePermissionActionTitle) {
                        appModel.resolveMicrophoneAccess()
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
            }
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

            MacSettingsStatusBadge(text: statusText, tint: tint)
            actions()
        }
        .padding(.vertical, 2)
    }
}

struct MacRequiredPermissionsGateView: View {
    @EnvironmentObject private var appModel: MacAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Permissions Required")
                    .font(.title2.weight(.semibold))

                Text("Stet needs microphone access to capture dictation and text injection access to write the final text back into your current app.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    permissionGateRow(
                        title: "Microphone",
                        description: "Required before any recording can start.",
                        statusText: appModel.microphoneAccessStatusText,
                        tint: appModel.microphoneAccessNeedsAttention ? .orange : .green
                    ) {
                        if appModel.microphoneAccessNeedsAttention {
                            Button(appModel.microphonePermissionActionTitle) {
                                appModel.resolveMicrophoneAccess()
                            }
                        }
                    }

                    permissionGateRow(
                        title: "Text Injection",
                        description: "Required so Stet can paste or replace text in other apps.",
                        statusText: appModel.autoPasteStatusText,
                        tint: appModel.autoPasteAccessNeedsAttention ? .orange : .green
                    ) {
                        if appModel.autoPasteAccessNeedsAttention {
                            Button("Request Access") {
                                appModel.requestAutoPasteAccess()
                            }

                            Button("Open Settings") {
                                appModel.openAccessibilitySettings()
                            }
                        }
                    }
                }
                .padding(8)
            }

            HStack(spacing: 12) {
                Button("Quit Stet") {
                    NSApplication.shared.terminate(nil)
                }

                Spacer()

                Text("Stet unlocks automatically after macOS grants both permissions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    @ViewBuilder
    private func permissionGateRow<Actions: View>(
        title: String,
        description: String,
        statusText: String,
        tint: Color,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                MacSettingsStatusBadge(text: statusText, tint: tint)
            }

            HStack(spacing: 8) {
                actions()
            }
        }
    }

}
#endif
