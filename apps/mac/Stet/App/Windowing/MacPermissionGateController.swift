#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class MacPermissionGateController: MacPermissionGatePresenting {
    private var windowController: NSWindowController?

    func show(appModel: any MacPermissionsCoordinating) {
        hide()
    }

    func hide() {
        windowController?.close()
        windowController = nil
    }
}
#endif
