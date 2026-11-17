#if os(macOS)
    import StetCore
    import SwiftUI

    struct MacModelCatalogUpdateControls: View {
        let refreshState: RewriteModelCatalogStore.RefreshState
        let revision: Int
        let check: () -> Void

        var body: some View {
            LinearSettingRow(
                "Model Catalog",
                subtitle: "Catalog revision \(revision)"
            ) {
                HStack(spacing: 10) {
                    if refreshState != .idle {
                        HStack(spacing: 5) {
                            Image(systemName: statusIcon)
                                .font(.system(size: 11))
                            Text(statusText)
                                .font(MacUI.LinearTypography.badge)
                        }
                        .foregroundStyle(statusColor)
                    }

                    Button("Check for Model Updates", action: check)
                        .buttonStyle(.bordered)
                        .disabled(refreshState == .checking)
                }
            }
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
            case .updated, .upToDate: MacUI.Foreground.success
            case .failed: MacUI.Foreground.error
            case .idle, .checking: MacUI.Foreground.secondaryColor
            }
        }
    }
#endif
