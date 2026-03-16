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

            if appModel.hasHistory {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Captures")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    ForEach(appModel.displayedHistory.prefix(3)) { record in
                        Button {
                            appModel.copyToClipboard(record: record)
                        } label: {
                            recentCaptureRow(for: record)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                menuRow(
                    title: "Quit airType",
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
                Text("airType")
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

    private func recentCaptureRow(for record: TranscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.metadata.kind.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(historyBadgeColor(for: record))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(historyBadgeColor(for: record).opacity(0.12))
                    )

                Text(record.text)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                if appModel.didCopyRecord(record) {
                    Text("Copied")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
            }

            Text(Self.relativeFormatter.localizedString(for: record.createdAt, relativeTo: .now))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
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

    private func historyBadgeColor(for record: TranscriptionRecord) -> Color {
        switch record.metadata.kind {
        case .dictation:
            return .blue
        case .translation:
            return .green
        case .rewrite:
            return .orange
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

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
#endif
