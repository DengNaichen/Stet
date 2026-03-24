#if os(macOS)
    import AppKit
    import SwiftUI

    @MainActor
    final class MacOnboardingWindowController {
        private var windowController: NSWindowController?

        func show(appModel: any MacPermissionsCoordinating) {
            if let window = windowController?.window {
                guard !window.isVisible else {
                    return
                }

                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }

                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let hostingController = NSHostingController(rootView: OnboardingView(appModel: appModel))
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Stet Onboarding"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 900, height: 680))
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
