#if os(macOS)
    import AppKit
    import SwiftUI

    struct MacDictationAppUsageView: View {
        let apps: [DictationAppUsage]

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("By app")
                    .font(.headline)

                if apps.isEmpty {
                    Text("App breakdown starts after your next dictation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 12) {
                        ForEach(apps) { app in
                            row(for: app)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(MacUI.Surfaces.selection)
            )
        }

        private func row(for app: DictationAppUsage) -> some View {
            HStack(alignment: .center, spacing: 10) {
                icon(for: app)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(app.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MacUI.Surfaces.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(app.formattedWordCount)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(MacUI.Surfaces.ink)
                    }

                    HStack(spacing: 8) {
                        shareBar(share: app.share)
                        Text(app.formattedSessionCount)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
        }

        private func shareBar(share: Double) -> some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MacUI.Surfaces.ink.opacity(0.08))
                    Capsule()
                        .fill(MacUI.Brand.orange)
                        .frame(width: max(4, geo.size.width * CGFloat(min(max(share, 0), 1))))
                }
            }
            .frame(height: 5)
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
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                placeholderIcon("app.dashed")
            }
        }

        private func placeholderIcon(_ systemName: String) -> some View {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(MacUI.Surfaces.ink.opacity(0.08))
                )
        }
    }
#endif
