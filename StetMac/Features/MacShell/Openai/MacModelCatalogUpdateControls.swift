#if os(macOS)
    import SwiftUI
    import StetCore

    struct MacModelCatalogUpdateControls: View {
        let refreshState: RewriteModelCatalogStore.RefreshState
        let revision: Int
        let check: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Check for Model Updates", action: check)
                        .disabled(refreshState == .checking)
                    Text("Catalog revision \(revision)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Image(systemName: statusIcon).frame(width: 16)
                    Text(statusText)
                }
                .font(.callout)
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .frame(height: 20, alignment: .leading)
                .opacity(refreshState == .idle ? 0 : 1)
                .accessibilityHidden(refreshState == .idle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var statusText: LocalizedStringKey {
            switch refreshState {
            case .idle, .checking: "Checking model catalog…"
            case .updated, .upToDate: "Updated"
            case .failed: "Check failed. Using current models."
            }
        }

        private var statusIcon: String {
            switch refreshState {
            case .idle, .checking: "arrow.triangle.2.circlepath"
            case .updated, .upToDate: "checkmark.circle.fill"
            case .failed: "exclamationmark.circle.fill"
            }
        }

        private var statusColor: Color {
            switch refreshState {
            case .updated, .upToDate: .green
            case .failed: .red
            case .idle, .checking: .secondary
            }
        }
    }

#endif
