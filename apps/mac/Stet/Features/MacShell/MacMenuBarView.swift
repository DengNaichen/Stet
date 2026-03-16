#if os(macOS)
import Foundation
import SwiftUI

struct MacMenuBarView: View {
    @EnvironmentObject private var appModel: MacAppModel
    @EnvironmentObject private var appUpdateManager: AppUpdateManager
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

//            menuButton(
//                title: appModel.primaryButtonTitle,
//                systemImage: primarySymbolName,
//                shortcut: appModel.hotkeyDisplayString,
//                isProminent: true,
//                action: appModel.performPrimaryAction
//            )
//            .disabled(isBusy)

            menuButton(
                title: appModel.panelButtonTitle,
                systemImage: "capsule.portrait",
                action: appModel.togglePanel
            )

//            menuButton(
//                title: appModel.translationButtonTitle,
//                systemImage: "globe",
//                shortcut: appModel.hotkeyShortcut(for: .translation)?.displayString,
//                action: appModel.performTranslationAction
//            )
            .disabled(alternateActionsDisabled)

//            menuButton(
//                title: appModel.rewriteButtonTitle,
//                systemImage: "wand.and.stars",
//                shortcut: appModel.hotkeyShortcut(for: .rewrite)?.displayString,
//                action: appModel.performRewriteAction
//            )
//            .disabled(alternateActionsDisabled)

            Button {
                appModel.openSettings {
                    openSettings()
                }
            } label: {
                menuRow(
                    title: "Settings…",
                    systemImage: "gearshape",
                    shortcut: "⌘,"
                )
            }
            .buttonStyle(.plain)

            menuButton(
                title: appUpdateMenuTitle,
                systemImage: "arrow.down.circle",
                action: appUpdateManager.checkForUpdates
            )
            .disabled(appUpdateManager.isChecking || !appUpdateManager.canCheckForUpdates)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                menuRow(
                    title: "Quit Stet",
                    systemImage: "power",
                    shortcut: "⌘Q"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 264)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text("Stet")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))

                Text(appModel.statusText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func menuButton(
        title: String,
        systemImage: String,
        shortcut: String? = nil,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            menuRow(
                title: title,
                systemImage: systemImage,
                shortcut: shortcut,
                isProminent: isProminent
            )
        }
        .buttonStyle(.plain)
    }

    private func menuRow(
        title: String,
        systemImage: String,
        shortcut: String? = nil,
        isProminent: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16)
                .foregroundStyle(isProminent ? .white : .primary)

            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(isProminent ? .white : .primary)

            Spacer(minLength: 12)

            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isProminent ? Color.white.opacity(0.82) : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isProminent ? Color.accentColor : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var isBusy: Bool {
        if case .processing = appModel.dictationViewModel.state {
            return true
        }

        return false
    }

    private var alternateActionsDisabled: Bool {
        switch appModel.dictationViewModel.state {
        case .idle, .result, .error:
            return false
        case .listening, .processing:
            return true
        }
    }

    private var statusColor: Color {
        switch appModel.dictationViewModel.state {
        case .idle:
            return .blue
        case .listening:
            return .red
        case .processing:
            return .orange
        case .result:
            return .green
        case .error:
            return .yellow
        }
    }

    private var primarySymbolName: String {
        switch appModel.dictationViewModel.state {
        case .idle, .result, .error:
            return "mic.fill"
        case .listening:
            return "stop.fill"
        case .processing:
            return "hourglass"
        }
    }

    private var appUpdateMenuTitle: String {
        switch appUpdateManager.state {
        case .updateAvailable(_, let latestVersion):
            return "Update Available (\(latestVersion))"
        case .checking:
            return "Checking for Updates…"
        case .unavailable:
            return "Updates Unavailable"
        default:
            return "Check for Updates…"
        }
    }
}
#endif
