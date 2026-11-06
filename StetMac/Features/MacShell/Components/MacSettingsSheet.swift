#if os(macOS)
    import AppKit
    import SwiftUI

    extension View {
        func macSettingsSheet<Sheet: View>(
            isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Sheet
        ) -> some View {
            background(MacSettingsSheetPresenter(isPresented: isPresented, sheet: content))
        }
    }

    /// A real modal panel keeps keyboard focus and Escape behavior while using Stet's surface tokens.
    private struct MacSettingsSheetPresenter<Sheet: View>: NSViewRepresentable {
        @Binding var isPresented: Bool
        @ViewBuilder var sheet: () -> Sheet
        @Environment(\.colorScheme) private var colorScheme

        func makeCoordinator() -> MacSettingsSheetCoordinator { MacSettingsSheetCoordinator() }
        func makeNSView(context: Context) -> MacSettingsSheetAnchorView { MacSettingsSheetAnchorView() }

        func updateNSView(_ view: MacSettingsSheetAnchorView, context: Context) {
            let coordinator = context.coordinator
            view.presentWhenAttached = nil
            coordinator.dismiss = { isPresented = false }
            coordinator.wantsPresentation = isPresented
            if !isPresented {
                coordinator.close()
                return
            }
            let root = sheet().environment(\.colorScheme, colorScheme)
            if coordinator.panel != nil {
                // The panel has its own hosting tree; refresh values derived from parent state.
                coordinator.update(root)
                return
            }
            view.presentWhenAttached = { [weak view, weak coordinator] in
                guard let parent = view?.window, let coordinator,
                    coordinator.panel == nil, coordinator.wantsPresentation
                else { return }
                coordinator.present(root, on: parent)
            }
            view.schedulePresentation()
        }

        static func dismantleNSView(_ nsView: MacSettingsSheetAnchorView, coordinator: MacSettingsSheetCoordinator) {
            nsView.presentWhenAttached = nil
            coordinator.wantsPresentation = false
            coordinator.close()
        }

    }

    private final class MacSettingsSheetAnchorView: NSView {
        var presentWhenAttached: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { schedulePresentation() }
        }

        func schedulePresentation() {
            DispatchQueue.main.async { [weak self] in
                self?.presentWhenAttached?()
            }
        }
    }

    private final class MacSettingsSheetCoordinator: NSObject {
        var panel: MacSettingsEditorPanel?
        var dismiss: (() -> Void)?
        var wantsPresentation = false
        private var host: NSHostingView<AnyView>?

        func update<Root: View>(_ root: Root) {
            guard let panel else { return }
            host?.rootView = hostedRoot(root, panel: panel)
        }

        private func hostedRoot<Root: View>(_ root: Root, panel: NSPanel) -> AnyView {
            AnyView(
                root.fixedSize().background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: EditorSizeKey.self, value: geometry.size)
                    }
                }.onPreferenceChange(EditorSizeKey.self) { [weak panel] size in
                    guard size.width > 0, size.height > 0 else { return }
                    DispatchQueue.main.async { panel?.setContentSize(size) }
                })
        }

        func present<Root: View>(_ root: Root, on parent: NSWindow) {
            let panel = MacSettingsEditorPanel(
                contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            self.panel = panel
            panel.onCancel = { [weak self] in self?.dismiss?() }
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: hostedRoot(root, panel: panel))
            self.host = host
            panel.contentView = host
            panel.setContentSize(host.fittingSize)
            parent.beginSheet(panel)
            // Hosting can apply native window chrome while attaching. Restore the token-shaped surface.
            panel.styleMask = [.borderless]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.makeKeyAndOrderFront(nil)
        }

        func close() {
            guard let panel else { return }
            self.panel = nil
            host = nil
            panel.sheetParent?.endSheet(panel)
            panel.orderOut(nil)
        }
    }

    // Keep AppKit subclasses outside the generic presenter: Swift 6.3's Intel
    // Release optimizer crashes on the nested class's MainActor-isolated deinit.
    private final class MacSettingsEditorPanel: NSPanel {
        var onCancel: (() -> Void)?
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
        override func cancelOperation(_ sender: Any?) { onCancel?() }
    }

    private struct EditorSizeKey: PreferenceKey {
        static let defaultValue: CGSize = .zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
    }

#endif
