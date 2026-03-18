#if os(macOS)
import AppKit
import SwiftUI

struct MacRequiredPermissionsGateView: View {
    @StateObject private var viewModel: MacPermissionsViewModel

    init(appModel: any MacPermissionsCoordinating) {
        _viewModel = StateObject(wrappedValue: MacPermissionsViewModel(coordinator: appModel))
    }

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
                        statusText: viewModel.microphoneAccessStatusText,
                        tint: viewModel.microphoneAccessNeedsAttention ? .orange : .green
                    ) {
                        if viewModel.microphoneAccessNeedsAttention {
                            Button(viewModel.microphonePermissionActionTitle) {
                                viewModel.resolveMicrophoneAccess()
                            }
                        }
                    }

                    permissionGateRow(
                        title: "Text Injection",
                        description: "Required so Stet can paste or replace text in other apps.",
                        statusText: viewModel.autoPasteStatusText,
                        tint: viewModel.autoPasteAccessNeedsAttention ? .orange : .green
                    ) {
                        if viewModel.autoPasteAccessNeedsAttention {
                            Button("Request Access") {
                                viewModel.requestAutoPasteAccess()
                            }

                            Button("Open Settings") {
                                viewModel.openAccessibilitySettings()
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
