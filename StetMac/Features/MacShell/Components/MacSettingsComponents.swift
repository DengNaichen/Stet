#if os(macOS)
    import AppKit
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

    struct StetWaveMark: Shape {
        func path(in rect: CGRect) -> Path {
            let sx = rect.width / 16
            let sy = rect.height / 10
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * sx, y: y * sy)
            }

            var path = Path()
            path.move(to: point(1, 6.5))
            path.addCurve(to: point(3.6, 3.2), control1: point(2.2, 6.5), control2: point(2.4, 3.2))
            path.addCurve(to: point(6.4, 8.2), control1: point(4.8, 3.2), control2: point(5, 8.2))
            path.addCurve(to: point(9.6, 1.8), control1: point(7.8, 8.2), control2: point(8, 1.8))
            path.addCurve(to: point(13, 6), control1: point(11.2, 1.8), control2: point(11.4, 6))
            path.addCurve(to: point(15.2, 5.2), control1: point(13.8, 6), control2: point(14.4, 5.2))
            return path
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
                .padding(.horizontal, MacUI.SettingsViewMetrics.detailHorizontalPadding)
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

    struct MacSettingsWindowChrome: NSViewRepresentable {
        var trafficLightLeading: CGFloat
        var trafficLightTop: CGFloat
        var scrollerRevision: String

        func makeNSView(context: Context) -> NSView {
            MacSettingsWindowChromeView(
                trafficLightLeading: trafficLightLeading,
                trafficLightTop: trafficLightTop
            )
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            _ = scrollerRevision
            guard let view = nsView as? MacSettingsWindowChromeView else { return }
            view.trafficLightLeading = trafficLightLeading
            view.trafficLightTop = trafficLightTop
            view.applyWindowChrome()
        }
    }

    private final class MacSettingsWindowChromeView: NSView {
        var trafficLightLeading: CGFloat
        var trafficLightTop: CGFloat

        init(trafficLightLeading: CGFloat, trafficLightTop: CGFloat) {
            self.trafficLightLeading = trafficLightLeading
            self.trafficLightTop = trafficLightTop
            super.init(frame: .zero)
            isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidChange),
                    name: NSWindow.didResizeNotification,
                    object: window
                )
            }
            DispatchQueue.main.async { [weak self] in
                self?.applyWindowChrome()
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func windowDidChange() {
            applyWindowChrome()
        }

        func applyWindowChrome() {
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.backgroundColor = MacUI.Surfaces.hubFill
            configureScrollers(in: window.contentView)

            for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = false
            }

            DispatchQueue.main.async { [weak self] in
                self?.reinstallScrollers()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.reinstallScrollers()
            }
        }

        private func reinstallScrollers() {
            guard let contentView = window?.contentView else { return }
            configureScrollers(in: contentView)
        }

        private func configureScrollers(in view: NSView?) {
            guard let view else { return }
            if let scrollView = view as? NSScrollView {
                MacThinOverlayScroller.install(on: scrollView)
            }
            for subview in view.subviews {
                configureScrollers(in: subview)
            }
        }
    }

    /// Overlay thumb only: no track/gutter, so content stays centered and the
    /// scroller never reads as a column divider.
    private final class MacThinOverlayScroller: NSScroller {
        override class var isCompatibleWithOverlayScrollers: Bool { true }

        override class func scrollerWidth(
            for controlSize: NSControl.ControlSize,
            scrollerStyle: NSScroller.Style
        ) -> CGFloat {
            MacUI.SettingsViewMetrics.overlayScrollerWidth
        }

        static func install(on scrollView: NSScrollView) {
            scrollView.scrollerStyle = .overlay
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.horizontalScrollElasticity = .none
            scrollView.scrollerInsets = NSEdgeInsets()
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear

            if !(scrollView.verticalScroller is MacThinOverlayScroller) {
                let scroller = MacThinOverlayScroller()
                scroller.controlSize = .mini
                scroller.scrollerStyle = .overlay
                scrollView.verticalScroller = scroller
            }

            scrollView.verticalScroller?.scrollerStyle = .overlay
        }

        override func draw(_ dirtyRect: NSRect) {
            guard alphaValue > 0.01 else { return }
            drawKnob()
        }

        override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

        override func drawArrow(_ arrow: NSScroller.Arrow, highlight flag: Bool) {}

        override func drawKnob() {
            guard knobProportion < 0.999 else { return }

            let knob = rect(for: .knob)
            guard knob.height > 1, knob.width > 0 else { return }

            let width = MacUI.SettingsViewMetrics.overlayScrollerKnobWidth
            let rect = NSRect(
                x: knob.midX - (width / 2),
                y: knob.minY,
                width: width,
                height: knob.height
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2)
            knobFillColor.setFill()
            path.fill()
        }

        private var knobFillColor: NSColor {
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(white: isDark ? 1 : 0, alpha: isDark ? 0.32 : 0.22)
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
