#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class MacPermissionGateController {
    private var windowController: NSWindowController?

    func show(appModel: MacAppModel) {
        if windowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Permissions Required"
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.center()
            window.level = .floating

            let view = MacRequiredPermissionsGateView()
                .environmentObject(appModel)
            window.contentView = NSHostingView(rootView: view)

            windowController = NSWindowController(window: window)
        }
        
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        windowController?.close()
        windowController = nil
    }
}
#endif
