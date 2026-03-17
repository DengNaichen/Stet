#if os(macOS)
import AppKit
import ApplicationServices
import Foundation

@MainActor
struct TextInjectionAccessState: Equatable {
    let hasAccessibilityAccess: Bool
    let hasPostEventAccess: Bool

    var canSimulateInput: Bool {
        hasAccessibilityAccess || hasPostEventAccess
    }
}

@MainActor
protocol TextInjectionService {
    var accessState: TextInjectionAccessState { get }
    var isAvailable: Bool { get }

    func requestAccess()
    func requestAccessIfNeeded()
    func openAccessibilitySettings()
    func pasteClipboard(into application: NSRunningApplication?) async -> Bool
    func selectedText() -> String?
    func replaceSelectedText(
        _ text: String,
        into application: NSRunningApplication?,
        keepResultInClipboard: Bool
    ) async -> Bool
}

@MainActor
final class SystemTextInjectionService: TextInjectionService {
    private enum KeyCode {
        static let copy: CGKeyCode = 8
        static let paste: CGKeyCode = 9
    }

    private let clipboardService: any ClipboardService
    private var didPromptForMissingAccessThisSession = false

    init(clipboardService: any ClipboardService) {
        self.clipboardService = clipboardService
    }

    var accessState: TextInjectionAccessState {
        .init(
            hasAccessibilityAccess: AXIsProcessTrusted(),
            hasPostEventAccess: CGPreflightPostEventAccess()
        )
    }

    var isAvailable: Bool {
        accessState.canSimulateInput
    }

    func requestAccess() {
        didPromptForMissingAccessThisSession = true
        requestMissingAccesses(trigger: "manual")
    }

    func requestAccessIfNeeded() {
        guard !isAvailable, !didPromptForMissingAccessThisSession else {
            return
        }

        didPromptForMissingAccessThisSession = true
        requestMissingAccesses(trigger: "automatic")
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func pasteClipboard(into application: NSRunningApplication?) async -> Bool {
        guard accessState.canSimulateInput else {
            return false
        }

        if let application,
           !application.isTerminated,
           application.bundleIdentifier != Bundle.main.bundleIdentifier {
            _ = application.activate()
            try? await Task.sleep(for: .milliseconds(180))
        }

        try? await Task.sleep(for: .milliseconds(60))
        return simulateCommandKey(KeyCode.paste)
    }

    func selectedText() -> String? {
        if let axSelected = selectedTextFromAXFocusedElement(),
           !axSelected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return axSelected
        }

        return selectedTextBySimulatedCopy()
    }

    func replaceSelectedText(
        _ text: String,
        into application: NSRunningApplication?,
        keepResultInClipboard: Bool
    ) async -> Bool {
        guard !text.isEmpty else { return false }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        clipboardService.copy(text)
        let didPaste = await pasteClipboard(into: application)

        guard didPaste, !keepResultInClipboard else {
            return didPaste
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            snapshot.restore(to: pasteboard)
        }

        return didPaste
    }

    private func selectedTextFromAXFocusedElement() -> String? {
        guard accessState.hasAccessibilityAccess else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard focusedStatus == .success,
              let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else {
            return nil
        }

        let focusedElement = unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        var selectedTextRef: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )
        guard selectedStatus == .success,
              let selectedTextRef else {
            return nil
        }

        if let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
            return selectedText
        }

        if let selectedText = selectedTextRef as? NSAttributedString, !selectedText.string.isEmpty {
            return selectedText.string
        }

        return nil
    }

    private func selectedTextBySimulatedCopy() -> String? {
        guard accessState.canSimulateInput else { return nil }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let originalChangeCount = pasteboard.changeCount

        guard simulateCommandKey(KeyCode.copy) else { return nil }
        Thread.sleep(forTimeInterval: 0.06)

        let copiedChangeCount = pasteboard.changeCount
        guard copiedChangeCount != originalChangeCount else {
            return nil
        }

        defer {
            snapshot.restore(to: pasteboard)
        }

        let copied = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let copied, !copied.isEmpty else { return nil }
        return copied
    }

    private func simulateCommandKey(_ keyCode: CGKeyCode) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func requestMissingAccesses(trigger: String) {
        let state = accessState
        AppLogger.info(
            "Requesting text injection permissions. trigger=\(trigger), accessibility=\(state.hasAccessibilityAccess), postEvent=\(state.hasPostEventAccess)",
            category: .permissions
        )

        if !state.hasPostEventAccess {
            _ = CGRequestPostEventAccess()
        }

        if !state.hasAccessibilityAccess {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
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

            guard !restoredItems.isEmpty else { return }
            pasteboard.writeObjects(restoredItems)
        }
    }
}
#endif
