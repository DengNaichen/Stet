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

    extension View {
        func macSettingsSheet<Sheet: View>(
            isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Sheet
        ) -> some View {
            background(MacSettingsSheetPresenter(isPresented: isPresented, sheet: content))
        }
    }

    /// A real modal panel keeps keyboard focus and Escape behavior while using Stet's surface tokens.
    private struct MacSettingsSheetPresenter<Sheet: View>: NSViewRepresentable {
        @Binding var isPresented: Bool
        @ViewBuilder var sheet: () -> Sheet
        @Environment(\.colorScheme) private var colorScheme

        func makeCoordinator() -> MacSettingsSheetCoordinator { MacSettingsSheetCoordinator() }
        func makeNSView(context: Context) -> NSView { NSView() }

        func updateNSView(_ view: NSView, context: Context) {
            let coordinator = context.coordinator
            coordinator.dismiss = { isPresented = false }
            coordinator.wantsPresentation = isPresented
            if !isPresented {
                coordinator.close()
                return
            }
            guard coordinator.panel == nil else { return }
            let root = sheet().environment(\.colorScheme, colorScheme)
            DispatchQueue.main.async { [weak view] in
                guard let parent = view?.window, coordinator.panel == nil, coordinator.wantsPresentation else { return }
                coordinator.present(root, on: parent)
            }
        }

        static func dismantleNSView(_ nsView: NSView, coordinator: MacSettingsSheetCoordinator) { coordinator.close() }

    }

    private final class MacSettingsSheetCoordinator: NSObject {
        var panel: MacSettingsEditorPanel?
        var dismiss: (() -> Void)?
        var wantsPresentation = false

        func present<Root: View>(_ root: Root, on parent: NSWindow) {
            let panel = MacSettingsEditorPanel(
                contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            self.panel = panel
            panel.onCancel = { [weak self] in self?.dismiss?() }
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            let host = NSHostingView(
                rootView: root.fixedSize().background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: EditorSizeKey.self, value: geometry.size)
                    }
                }.onPreferenceChange(EditorSizeKey.self) { [weak panel] size in
                    guard size.width > 0, size.height > 0 else { return }
                    DispatchQueue.main.async { panel?.setContentSize(size) }
                })
            panel.contentView = host
            panel.setContentSize(host.fittingSize)
            parent.beginSheet(panel)
            // Hosting can apply native window chrome while attaching. Restore the token-shaped surface.
            panel.styleMask = [.borderless]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.makeKeyAndOrderFront(nil)
        }

        func close() {
            guard let panel else { return }
            self.panel = nil
            panel.sheetParent?.endSheet(panel)
            panel.orderOut(nil)
        }
    }

    // Keep AppKit subclasses outside the generic presenter: Swift 6.3's Intel
    // Release optimizer crashes on the nested class's MainActor-isolated deinit.
    private final class MacSettingsEditorPanel: NSPanel {
        var onCancel: (() -> Void)?
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
        override func cancelOperation(_ sender: Any?) { onCancel?() }
    }

    private struct EditorSizeKey: PreferenceKey {
        static let defaultValue: CGSize = .zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
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
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollViewsChanged(_:)),
                name: NSScrollView.willStartLiveScrollNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollViewsChanged(_:)),
                name: NSScrollView.didLiveScrollNotification,
                object: nil
            )
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

        @objc private func scrollViewsChanged(_ notification: Notification) {
            guard let scrollView = notification.object as? NSScrollView,
                scrollView.window === window
            else { return }
            hideNativeScrollers(in: window?.contentView)
        }

        func applyWindowChrome() {
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.backgroundColor = MacUI.Surfaces.hubFill

            for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = false
            }

            hideNativeScrollers(in: window.contentView)
            DispatchQueue.main.async { [weak self] in
                self?.hideNativeScrollers(in: self?.window?.contentView)
            }
        }

        private func hideNativeScrollers(in view: NSView?) {
            guard let view else { return }
            if let scrollView = view as? NSScrollView {
                MacInvisibleScroller.install(on: scrollView)
            }
            for subview in view.subviews {
                hideNativeScrollers(in: subview)
            }
        }
    }

    /// SwiftUI keeps re-enabling AppKit overlay scrollers after a one-shot hide.
    /// A zero-width scroller stays installed so the sidebar never redraws a thumb.
    private final class MacInvisibleScroller: NSScroller {
        override class var isCompatibleWithOverlayScrollers: Bool { true }

        override class func scrollerWidth(
            for controlSize: NSControl.ControlSize,
            scrollerStyle: NSScroller.Style
        ) -> CGFloat {
            0
        }

        static func install(on scrollView: NSScrollView) {
            scrollView.scrollerStyle = .overlay
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.horizontalScrollElasticity = .none
            if !(scrollView.verticalScroller is MacInvisibleScroller) {
                let scroller = MacInvisibleScroller()
                scroller.scrollerStyle = .overlay
                scroller.alphaValue = 0
                scroller.isHidden = true
                scrollView.verticalScroller = scroller
            }
            scrollView.verticalScroller?.alphaValue = 0
            scrollView.verticalScroller?.isHidden = true
        }

        override func draw(_ dirtyRect: NSRect) {}

        override func drawKnob() {}

        override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
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
