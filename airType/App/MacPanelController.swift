#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class MacPanelController: NSObject, NSWindowDelegate {
    enum PresentationMode {
        case manual
        case transient
    }

    private enum Constants {
        static let width: CGFloat = 340
        static let height: CGFloat = 92
        static let bottomInset: CGFloat = 30
    }

    private final class CapsulePanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private var panel: NSPanel?
    private weak var appModel: MacAppModel?

    func show(appModel: MacAppModel, mode: PresentationMode) {
        self.appModel = appModel

        if panel == nil {
            panel = makePanel(appModel: appModel)
        }

        guard let panel else { return }

        panel.contentViewController = NSHostingController(
            rootView: MacDictationPanelView()
                .environmentObject(appModel)
        )

        positionPanel(panel)
        panel.orderFrontRegardless()

        if mode == .manual {
            panel.makeKey()
        }
    }

    func hide() {
        panel?.orderOut(nil)
        appModel?.panelDidHide()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    private func makePanel(appModel: MacAppModel) -> NSPanel {
        let panel = CapsulePanel(
            contentRect: NSRect(x: 0, y: 0, width: Constants.width, height: Constants.height),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentViewController = NSHostingController(
            rootView: MacDictationPanelView()
                .environmentObject(appModel)
        )

        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = targetScreen() else {
            panel.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let origin = CGPoint(
            x: visibleFrame.midX - (Constants.width / 2),
            y: visibleFrame.minY + Constants.bottomInset
        )

        panel.setFrameOrigin(origin)
    }

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation

        if let hoveredScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return hoveredScreen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }
}
#endif
