#if os(macOS)
    import SwiftUI

    // MARK: - App Form Wrapper

    struct AppForm<Content: View>: View {
        @ViewBuilder var content: () -> Content

        var body: some View {
            Form { content() }
                .macSettingsFormStyle()
                .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
        }
    }

#endif
