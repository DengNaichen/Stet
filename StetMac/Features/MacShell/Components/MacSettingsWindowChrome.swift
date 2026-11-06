#if os(macOS)
    import AppKit
    import SwiftUI

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

#endif
