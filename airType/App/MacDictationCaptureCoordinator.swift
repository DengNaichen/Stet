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
        if settings.shouldCopyToClipboard || settings.shouldAutoPaste {
            clipboardService.copy(text)
        }

        if settings.shouldAutoPaste {
            let didPaste = await textInjectionService.pasteClipboard(into: targetApplication)

            if !didPaste && !textInjectionService.isAvailable {
                textInjectionService.requestAccessIfNeeded()
            }

            if settings.shouldRevealPanelOnCapture && !didPaste {
                showPanel()
            }
        } else if settings.shouldRevealPanelOnCapture {
            showPanel()
        }
    }
}
#endif
