#if os(macOS)
    import AppKit
    import SwiftUI

    struct MacDictationAppUsageView: View {
        let apps: [DictationAppUsage]

        var body: some View {
            LinearSectionGroup("By app") {
                if apps.isEmpty {
                    Text("App breakdown starts after your next dictation.")
                        .font(MacUI.LinearTypography.rowSubtitle)
                        .foregroundStyle(MacUI.Foreground.secondary)
                        .padding(.horizontal, MacUI.LinearMetrics.rowHorizontalPadding)
                        .padding(.vertical, 12)
                } else {
                    ForEach(apps) { app in
                        row(for: app)
                    }
                }
            }
        }

        private func row(for app: DictationAppUsage) -> some View {
            HStack(alignment: .center, spacing: 10) {
                icon(for: app)
                    .frame(width: 20, height: 20)

                Group {
                    if app.id == DictationAppUsage.otherID {
                        Text("Other")
                    } else {
                        Text(verbatim: app.name)
                    }
                }
                .font(MacUI.LinearTypography.rowTitle)
                .foregroundStyle(MacUI.Foreground.primary)
                .lineLimit(1)
                .frame(minWidth: 96, alignment: .leading)

                shareBar(share: app.share)

                Text("\(app.sessionCount) sessions")
                    .font(MacUI.LinearTypography.rowSubtitle)
                    .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                    .fixedSize()

                Group {
                    if app.wordCount < 1000 {
                        Text("\(app.wordCount) words")
                    } else {
                        Text("\(DictationUsageSummary.formatCompactCount(app.wordCount)) words")
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(MacUI.Foreground.primary)
                .frame(minWidth: 56, alignment: .trailing)
            }
            .padding(.horizontal, MacUI.LinearMetrics.rowHorizontalPadding)
            .padding(.vertical, 9)
        }

        private func shareBar(share: Double) -> some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MacUI.LinearSurfaces.elevated)
                    Capsule()
                        .fill(MacUI.LinearBrand.accent)
                        .frame(width: max(4, geo.size.width * CGFloat(min(max(share, 0), 1))))
                }
            }
            .frame(height: 4)
        }

        @ViewBuilder
        private func icon(for app: DictationAppUsage) -> some View {
            if app.id == DictationAppUsage.otherID {
                placeholderIcon("square.stack")
            } else if let bundleID = app.bundleID,
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                placeholderIcon("app.dashed")
            }
        }

        private func placeholderIcon(_ systemName: String) -> some View {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MacUI.Foreground.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(MacUI.LinearSurfaces.elevated)
                )
        }
    }
#endif
