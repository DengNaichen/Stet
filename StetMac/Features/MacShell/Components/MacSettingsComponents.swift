#if os(macOS)
    import AppKit
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

    struct MacSettingsWindowChrome: NSViewRepresentable {
        var trafficLightLeading: CGFloat
        var trafficLightTop: CGFloat

        func makeNSView(context: Context) -> NSView {
            MacSettingsWindowChromeView(
                trafficLightLeading: trafficLightLeading,
                trafficLightTop: trafficLightTop
            )
        }

        func updateNSView(_ nsView: NSView, context: Context) {
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
        }

        private func configureScrollers(in view: NSView?) {
            guard let view else { return }
            if let scrollView = view as? NSScrollView {
                scrollView.scrollerStyle = .overlay
                scrollView.autohidesScrollers = true
                scrollView.hasHorizontalScroller = false
            }
            for subview in view.subviews {
                configureScrollers(in: subview)
            }
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
