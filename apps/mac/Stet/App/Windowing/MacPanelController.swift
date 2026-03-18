#if os(macOS)
import AppKit
import Combine
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
    private var panelStateCancellable: AnyCancellable?

    func show(appModel: any MacDictationPanelCoordinating, mode: PresentationMode) {
        let screen = targetScreen()
        let layout = MacDictationPanelLayout.for(screen: screen)
        let panelSize = layout.panelSize(for: appModel.dictationState)

        observePanelState(for: appModel)

        if panel == nil {
            panel = makePanel(appModel: appModel, layout: layout, panelSize: panelSize)
        }

        guard let panel else { return }

        panel.contentViewController = NSHostingController(
            rootView: MacDictationPanelView(layout: layout, appModel: appModel)
        )

        positionPanel(
            panel,
            screen: screen,
            panelSize: panelSize,
            bottomInset: layout.bottomInset,
            animate: false
        )
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

    private func makePanel(
        appModel: any MacDictationPanelCoordinating,
        layout: MacDictationPanelLayout,
        panelSize: CGSize
    ) -> NSPanel {
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

    private func positionPanel(
        _ panel: NSPanel,
        screen: NSScreen?,
        panelSize: CGSize,
        bottomInset: CGFloat,
        animate: Bool
    ) {
        guard let screen else {
            panel.setContentSize(panelSize)
            panel.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let frame = NSRect(
            x: visibleFrame.midX - (panelSize.width / 2),
            y: visibleFrame.minY + bottomInset,
            width: panelSize.width,
            height: panelSize.height
        )

        panel.setFrame(frame, display: true, animate: animate)
    }

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation

        if let hoveredScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return hoveredScreen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func observePanelState(for appModel: any MacDictationPanelCoordinating) {
        guard observedAppModel !== appModel else { return }

        observedAppModel = appModel
        panelStateCancellable = appModel.updates
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak appModel] _ in
                DispatchQueue.main.async { [weak self, weak appModel] in
                    guard let self, let appModel, let panel = self.panel else { return }

                    let screen = panel.screen ?? self.targetScreen()
                    let layout = MacDictationPanelLayout.for(screen: screen)
                    let panelSize = layout.panelSize(for: appModel.dictationState)

                    self.positionPanel(
                        panel,
                        screen: screen,
                        panelSize: panelSize,
                        bottomInset: layout.bottomInset,
                        animate: panel.isVisible
                    )
                }
            }
    }
}
#endif
