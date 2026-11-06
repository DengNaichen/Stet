#if os(macOS)
    import Combine
    import SwiftUI

    struct MacSettingsCard<Content: View>: View {
        let title: String
        let description: String?

        private let content: () -> Content

        init(
            title: String,
            description: String? = nil,
            @ViewBuilder content: @escaping () -> Content
        ) {
            self.title = title
            self.description = description
            self.content = content
        }

        var body: some View {
            GroupBox {
                VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                    Text(LocalizedStringKey(title))
                        .font(.headline)

                    if let description {
                        Text(LocalizedStringKey(description))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MacUI.SettingsViewMetrics.cardInnerPadding)
            }
        }
    }

    struct MacSettingsEditor<Content: View>: View {
        let title: String
        let subtitle: String
        @ViewBuilder let content: () -> Content

        var body: some View {
            VStack(alignment: .leading, spacing: MacUI.EditorMetrics.spacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
            .padding(MacUI.EditorMetrics.padding)
            .frame(width: MacUI.EditorMetrics.width)
            .background(MacUI.Surfaces.paper)
            .clipShape(RoundedRectangle(cornerRadius: MacUI.EditorMetrics.cornerRadius, style: .continuous))

        }
    }

    struct MacSettingsValueRow<Value: View>: View {
        let title: String

        private let value: () -> Value

        init(
            title: String,
            @ViewBuilder value: @escaping () -> Value
        ) {
            self.title = title
            self.value = value
        }

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: MacUI.SettingsViewMetrics.valueRowSpacing) {
                Text(LocalizedStringKey(title))
                    .foregroundStyle(.secondary)

                Spacer()

                value()
            }
        }
    }

    extension View {
        /// Standard grouped Settings rows on the document paper.
        func macSettingsFormStyle() -> some View {
            formStyle(.grouped)
                .groupBoxStyle(MacSettingsPaperGroupBoxStyle())
                .scrollContentBackground(.hidden)
                .backgroundStyle(MacUI.Surfaces.paper)
                .macSettingsTracksTitleScroll()
        }

        func macSettingsTracksTitleScroll() -> some View {
            modifier(MacSettingsTitleScrollModifier())
        }

        func macSettingsScrollIndicator() -> some View {
            modifier(MacSettingsScrollIndicatorModifier())
        }
    }

    /// Grouped Form uses GroupBox for its section surfaces. Remove only that
    /// chrome so the native grouped rows, switches, and separators stay intact.
    private struct MacSettingsPaperGroupBoxStyle: GroupBoxStyle {
        func makeBody(configuration: Configuration) -> some View {
            VStack(alignment: .leading) {
                configuration.label
                configuration.content
            }
        }
    }

    final class MacSettingsTitleScrollStore: ObservableObject {
        @Published var offset: CGFloat = 0

        func update(_ newValue: CGFloat) {
            let clamped = max(0, newValue)
            guard abs(offset - clamped) >= 0.5 else { return }
            offset = clamped
        }

        func reset() {
            guard offset != 0 else { return }
            offset = 0
        }
    }

    private struct MacSettingsTitleScrollStoreKey: EnvironmentKey {
        static let defaultValue: MacSettingsTitleScrollStore? = nil
    }

    extension EnvironmentValues {
        var macSettingsTitleScrollStore: MacSettingsTitleScrollStore? {
            get { self[MacSettingsTitleScrollStoreKey.self] }
            set { self[MacSettingsTitleScrollStoreKey.self] = newValue }
        }
    }

    struct MacSettingsCollapsingTitle: View {
        let title: String
        @ObservedObject var store: MacSettingsTitleScrollStore
        var horizontalPadding: CGFloat = MacUI.SettingsViewMetrics.detailHorizontalPadding

        var body: some View {
            let progress = min(1, store.offset / MacUI.SettingsViewMetrics.detailTitleCollapseDistance)
            let collapsedScale =
                MacUI.SettingsViewMetrics.detailTitleCollapsedSize
                / MacUI.SettingsViewMetrics.detailTitleExpandedSize

            Text(LocalizedStringKey(title))
                .font(
                    .system(
                        size: MacUI.SettingsViewMetrics.detailTitleExpandedSize,
                        weight: .semibold
                    )
                )
                .foregroundStyle(MacUI.Surfaces.ink)
                .scaleEffect(1 - ((1 - collapsedScale) * progress), anchor: .leading)
                .frame(
                    maxWidth: .infinity,
                    minHeight: MacUI.SettingsViewMetrics.headerHeight,
                    alignment: .leading
                )
                .padding(.bottom, 20)
                .padding(.horizontal, horizontalPadding)
        }
    }

    private struct MacSettingsTitleScrollModifier: ViewModifier {
        @Environment(\.macSettingsTitleScrollStore) private var store

        func body(content: Content) -> some View {
            content
                .contentMargins(
                    .horizontal,
                    MacUI.SettingsViewMetrics.detailHorizontalPadding,
                    for: .scrollContent
                )
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, offset in
                    store?.update(offset)
                }
        }
    }

    private struct MacSettingsScrollMetrics: Equatable {
        var offset: CGFloat = 0
        var viewportHeight: CGFloat = 0
        var contentHeight: CGFloat = 0

        var overflows: Bool { contentHeight > viewportHeight + 1 && viewportHeight > 0 }
    }

    /// Draw outside the Form's margins, without reserving a gutter or changing
    /// its native row layout. Both columns share the same thumb and fade timing.
    private struct MacSettingsScrollIndicatorModifier: ViewModifier {
        @Environment(\.colorScheme) private var colorScheme
        @State private var metrics = MacSettingsScrollMetrics()
        @State private var phase = ScrollPhase.idle
        @State private var isVisible = false
        @State private var activity = 0

        func body(content: Content) -> some View {
            content
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: MacSettingsScrollMetrics.self) { geometry in
                    MacSettingsScrollMetrics(
                        offset: geometry.contentOffset.y + geometry.contentInsets.top,
                        viewportHeight: geometry.containerSize.height,
                        contentHeight: geometry.contentSize.height
                            + geometry.contentInsets.top + geometry.contentInsets.bottom
                    )
                } action: { oldValue, newValue in
                    metrics = newValue
                    if newValue.overflows && oldValue.offset != newValue.offset {
                        showIndicator()
                    }
                }
                .onScrollPhaseChange { _, newPhase in
                    phase = newPhase
                    if newPhase.isScrolling && metrics.overflows {
                        showIndicator()
                    } else {
                        activity += 1
                    }
                }
                .overlay(alignment: .topTrailing) {
                    GeometryReader { proxy in
                        let height = min(proxy.size.height, metrics.viewportHeight)
                        let thumbHeight = min(
                            height, max(24, height * metrics.viewportHeight / max(1, metrics.contentHeight)))
                        let progress = min(
                            1, max(0, metrics.offset / max(1, metrics.contentHeight - metrics.viewportHeight)))
                        let width = MacUI.SettingsViewMetrics.overlayScrollerKnobWidth

                        Capsule()
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.32 : 0.22))
                            .frame(width: width, height: thumbHeight)
                            .offset(y: progress * (height - thumbHeight))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.trailing, (MacUI.SettingsViewMetrics.overlayScrollerWidth - width) / 2)
                            .opacity(isVisible && metrics.overflows ? 1 : 0)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .task(id: activity) {
                    guard activity > 0 else { return }
                    do {
                        try await Task.sleep(for: .milliseconds(650))
                    } catch {
                        return
                    }
                    guard !phase.isScrolling else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        isVisible = false
                    }
                }
        }

        private func showIndicator() {
            isVisible = true
            activity += 1
        }
    }

    struct MacSettingsStatusBadge: View {
        let text: String
        let tint: Color

        var body: some View {
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
