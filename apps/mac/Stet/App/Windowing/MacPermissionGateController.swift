#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class MacPermissionGateController: MacPermissionGatePresenting {
    private var windowController: NSWindowController?

    func show(appModel: any MacPermissionsCoordinating) {
        if windowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Set Up Stet"
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.center()
            window.level = .floating

            windowController = NSWindowController(window: window)
        }

        windowController?.window?.contentView = NSHostingView(
            rootView: MacRequiredPermissionsGateView(appModel: appModel)
        )
        windowController?.window?.setContentSize(NSSize(width: 760, height: 620))
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        windowController?.close()
        windowController = nil
    }
}
#endif
