#if os(macOS)
    import AppKit
    import SwiftUI

    @MainActor
    final class MacPaywallWindowController {
        private var windowController: NSWindowController?

        func show() {
            if windowController?.window?.isVisible == true { return }

            let view = PaywallView { [weak self] in
                self?.hide()
            }
            let hostingController = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Stet"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()

            let controller = NSWindowController(window: window)
            windowController = controller
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        func hide() {
            windowController?.close()
            windowController = nil
        }
    }
#endif
