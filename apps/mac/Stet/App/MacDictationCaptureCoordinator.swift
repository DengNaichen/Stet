#if os(macOS)
import AppKit
import Foundation

@MainActor
final class MacDictationCaptureCoordinator {
    struct CaptureSettings {
        let shouldCopyToClipboard: Bool
        let shouldAutoPaste: Bool
        let shouldRevealPanelOnCapture: Bool
    }

    private let clipboardService: any ClipboardService
    private let textInjectionService: any TextInjectionService

    init(
        clipboardService: any ClipboardService,
        textInjectionService: any TextInjectionService
    ) {
        self.clipboardService = clipboardService
        self.textInjectionService = textInjectionService
    }

    func handleCompletedCapture(
        text: String,
        targetApplication: NSRunningApplication?,
        settings: CaptureSettings,
        showPanel: @escaping @MainActor () -> Void
    ) async {
        let shouldRestoreClipboardAfterSuccessfulPaste = settings.shouldAutoPaste && !settings.shouldCopyToClipboard
        let pasteboardSnapshot = shouldRestoreClipboardAfterSuccessfulPaste
            ? PasteboardSnapshot.capture(from: NSPasteboard.general)
            : nil

        if settings.shouldCopyToClipboard || settings.shouldAutoPaste {
            clipboardService.copy(text)
        }

        if settings.shouldAutoPaste {
            let didPaste = await textInjectionService.pasteClipboard(into: targetApplication)

            if didPaste {
                if let pasteboardSnapshot {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        pasteboardSnapshot.restore(to: NSPasteboard.general)
                    }
                }
                await DictationLatencyProbe.shared.record(.systemWriteCompleted)
            } else {
                await DictationLatencyProbe.shared.record(.systemWriteFailed, note: "paste_failed")
            }

            if !didPaste && !textInjectionService.isAvailable {
                textInjectionService.requestAccessIfNeeded()
            }

            if settings.shouldRevealPanelOnCapture && !didPaste {
                showPanel()
            }
        } else if settings.shouldRevealPanelOnCapture {
            await DictationLatencyProbe.shared.record(.systemWriteSkipped, note: "auto_paste_disabled")
            showPanel()
        } else {
            await DictationLatencyProbe.shared.record(.systemWriteSkipped, note: "auto_paste_disabled")
        }
    }

    private struct PasteboardSnapshot {
        private let items: [[NSPasteboard.PasteboardType: Data]]

        static func capture(from pasteboard: NSPasteboard) -> Self {
            let items = (pasteboard.pasteboardItems ?? []).map { item in
                var payload: [NSPasteboard.PasteboardType: Data] = [:]

                for type in item.types {
                    if let data = item.data(forType: type) {
                        payload[type] = data
                    }
                }

                return payload
            }

            return Self(items: items)
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()

            let restoredItems = items.compactMap { payload -> NSPasteboardItem? in
                let item = NSPasteboardItem()
                var hasContent = false

                for (type, data) in payload {
                    if item.setData(data, forType: type) {
                        hasContent = true
                    }
                }

                return hasContent ? item : nil
            }

            if !restoredItems.isEmpty {
                pasteboard.writeObjects(restoredItems)
            }
        }
    }
}
#endif
