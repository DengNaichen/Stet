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
        private weak var observedAppModel: (any MacDictationPanelCoordinating)?

        func show(appModel: any MacDictationPanelCoordinating, mode: PresentationMode) {
            let screen = targetScreen()
            let layout = MacDictationPanelLayout.fixed
            let panelSize = layout.panelSize
            let panelFrame = frame(for: screen, panelSize: panelSize, bottomInset: layout.bottomInset)
            let isNewAppModel = observedAppModel !== appModel

            observedAppModel = appModel

            if panel == nil {
                panel = makePanel(panelSize: panelSize)
            }

            guard let panel else { return }

            if panel.contentViewController == nil || !panel.isVisible || isNewAppModel {
                // Keep the hosted SwiftUI tree alive while the panel is visible so
                // state-only updates do not restart the entrance animation.
                panel.contentViewController = NSHostingController(
                    rootView: MacDictationPanelView(layout: layout, appModel: appModel)
                )
            }

            positionPanel(panel, panelFrame: panelFrame, shouldCenter: screen == nil)
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

        private func makePanel(panelSize: CGSize) -> NSPanel {
            let panel = CapsulePanel(
                contentRect: NSRect(origin: .zero, size: panelSize),
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
            panel.animationBehavior = .none
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true

            return panel
        }

        private func frame(
            for screen: NSScreen?,
            panelSize: CGSize,
            bottomInset: CGFloat
        ) -> NSRect {
            guard let screen else {
                return NSRect(origin: .zero, size: panelSize)
            }

            let visibleFrame = screen.visibleFrame
            return NSRect(
                x: visibleFrame.midX - (panelSize.width / 2),
                y: visibleFrame.minY + bottomInset,
                width: panelSize.width,
                height: panelSize.height
            )
        }

        private func positionPanel(
            _ panel: NSPanel,
            panelFrame: NSRect,
            shouldCenter: Bool
        ) {
            if shouldCenter {
                if panel.frame.size != panelFrame.size {
                    panel.setContentSize(panelFrame.size)
                }
                panel.center()
                return
            }

            if panel.frame.size != panelFrame.size {
                panel.setContentSize(panelFrame.size)
            }

            if panel.frame.origin != panelFrame.origin {
                panel.setFrameOrigin(panelFrame.origin)
            }
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
