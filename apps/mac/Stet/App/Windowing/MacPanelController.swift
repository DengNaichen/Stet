#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class MacPanelController: NSObject, NSWindowDelegate {
    var onHide: (() -> Void)?

    enum PresentationMode {
        case manual
        case transient
    }

    private final class CapsulePanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private var panel: NSPanel?

    func show(appModel: any MacDictationPanelCoordinating, mode: PresentationMode) {
        let screen = targetScreen()
        let layout = MacDictationPanelLayout.for(screen: screen)

        if panel == nil {
            panel = makePanel(appModel: appModel, layout: layout)
        }

        guard let panel else { return }

        panel.contentViewController = NSHostingController(
            rootView: MacDictationPanelView(layout: layout, appModel: appModel)
        )

        positionPanel(panel, screen: screen, layout: layout)
        panel.orderFrontRegardless()

        if mode == .manual {
            panel.makeKey()
        }
    }

    func hide() {
        panel?.orderOut(nil)
        onHide?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    private func makePanel(appModel: any MacDictationPanelCoordinating, layout: MacDictationPanelLayout) -> NSPanel {
        let panel = CapsulePanel(
            contentRect: NSRect(origin: .zero, size: layout.panelSize),
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
            rootView: MacDictationPanelView(layout: layout, appModel: appModel)
        )

        return panel
    }

    private func positionPanel(_ panel: NSPanel, screen: NSScreen?, layout: MacDictationPanelLayout) {
        guard let screen else {
            panel.setContentSize(layout.panelSize)
            panel.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let frame = NSRect(
            x: visibleFrame.midX - (layout.panelSize.width / 2),
            y: visibleFrame.minY + layout.bottomInset,
            width: layout.panelSize.width,
            height: layout.panelSize.height
        )

        panel.setFrame(frame, display: false)
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
