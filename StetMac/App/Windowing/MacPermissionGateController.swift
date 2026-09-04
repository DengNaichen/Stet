#if os(macOS)
    import AppKit
    import SwiftUI

    @MainActor
    final class MacPermissionGateController: MacPermissionGatePresenting {
        private var windowController: NSWindowController?
        private var viewModel: RuntimePermissionFailureViewModel?

        func show(appModel: any MacPermissionsCoordinating) {
            // Prevent duplicate windows - reuse existing window if already visible
            if let window = windowController?.window {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            // Create ViewModel
            let viewModel = RuntimePermissionFailureViewModel(coordinator: appModel)

            // Create View with dismiss closure
            let rootView = RuntimePermissionFailureView(viewModel: viewModel) { [weak self] in
                self?.hide()
            }

            // Create NSHostingController wrapping the view
            let hostingController = NSHostingController(rootView: rootView)

            // Create NSWindow with floating level, titled and closable style mask
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Permissions Required"
            window.styleMask = [.titled, .closable]
            window.level = .floating
            window.isReleasedWhenClosed = false

            // Center window
            window.center()

            // Create window controller
            let controller = NSWindowController(window: window)
            self.viewModel = viewModel
            self.windowController = controller

            // Show window and activate app
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        func hide() {
            windowController?.close()
            windowController = nil
            viewModel = nil
        }
    }
#endif
