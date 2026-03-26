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
    enum TextInjectionOutcome: Equatable {
        case verifiedSuccess
        case eventPostedVerificationUnavailable
        case verificationFailed
        case eventPostFailed

        var didSucceed: Bool {
            switch self {
            case .verifiedSuccess:
                return true
            case .eventPostedVerificationUnavailable, .verificationFailed, .eventPostFailed:
                return false
            }
        }
    }

    @MainActor
    enum TextReplacementOutcome: Equatable {
        case replaced
        case clipboardWriteFailed
        case injectionFailed(TextInjectionOutcome)
    }

    @MainActor
    protocol TextInjectionService {
        var accessState: TextInjectionAccessState { get }
        var isAvailable: Bool { get }

        func requestAccess()
        func requestAccessIfNeeded()
        func openAccessibilitySettings()
        func pasteClipboard(into application: NSRunningApplication?) async -> TextInjectionOutcome
        func selectedText() -> String?
        func replaceSelectedText(
            _ text: String,
            into application: NSRunningApplication?,
            keepResultInClipboard: Bool
        ) async -> TextReplacementOutcome
    }

    @MainActor
    final class SystemTextInjectionService: TextInjectionService {
        private enum KeyCode {
            static let copy: CGKeyCode = 8
            static let paste: CGKeyCode = 9
        }

        private struct SelectionRange: Equatable {
            let location: Int
            let length: Int
        }

        private struct FocusedElementSnapshot: Equatable {
            let value: String?
            let selectedText: String?
            let selectionRange: SelectionRange?
            let numberOfCharacters: Int?

            var canVerifyPaste: Bool {
                value != nil || selectedText != nil || selectionRange != nil || numberOfCharacters != nil
            }

            func indicatesMutation(comparedTo previous: Self) -> Bool {
                if let value, let previousValue = previous.value, value != previousValue {
                    return true
                }
                if let selectedText, let previousSelectedText = previous.selectedText,
                    selectedText != previousSelectedText
                {
                    return true
                }
                if let selectionRange, let previousSelectionRange = previous.selectionRange,
                    selectionRange != previousSelectionRange
                {
                    return true
                }
                if let numberOfCharacters, let previousCount = previous.numberOfCharacters,
                    numberOfCharacters != previousCount
                {
                    return true
                }

                return (value != nil) != (previous.value != nil)
                    || (selectedText != nil) != (previous.selectedText != nil)
                    || (selectionRange != nil) != (previous.selectionRange != nil)
                    || (numberOfCharacters != nil) != (previous.numberOfCharacters != nil)
            }
        }

        private let clipboardService: any ClipboardService
        private let pasteboard: NSPasteboard
        private let pasteboardRestoreCoordinator: PasteboardRestoreCoordinator
        private var didPromptForMissingAccessThisSession = false

        init(
            clipboardService: any ClipboardService,
            pasteboard: NSPasteboard = .general,
            pasteboardRestoreCoordinator: PasteboardRestoreCoordinator? = nil
        ) {
            self.clipboardService = clipboardService
            self.pasteboard = pasteboard
            self.pasteboardRestoreCoordinator =
                pasteboardRestoreCoordinator ?? PasteboardRestoreCoordinator()
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
            guard
                let url = URL(
                    string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )
            else {
                return
            }

            NSWorkspace.shared.open(url)
        }

        func pasteClipboard(into application: NSRunningApplication?) async -> TextInjectionOutcome {
            guard accessState.canSimulateInput else {
                return .eventPostFailed
            }

            let snapshotBeforePaste = focusedElementSnapshot()

            if let application,
                !application.isTerminated,
                application.bundleIdentifier != Bundle.main.bundleIdentifier
            {
                _ = application.activate()
                try? await Task.sleep(for: .milliseconds(180))
            }

            try? await Task.sleep(for: .milliseconds(60))
            guard simulateCommandKey(KeyCode.paste) else {
                return .eventPostFailed
            }

            guard let snapshotBeforePaste, snapshotBeforePaste.canVerifyPaste else {
                return .eventPostedVerificationUnavailable
            }

            try? await Task.sleep(for: .milliseconds(180))

            guard let snapshotAfterPaste = focusedElementSnapshot() else {
                return .eventPostedVerificationUnavailable
            }

            return snapshotAfterPaste.indicatesMutation(comparedTo: snapshotBeforePaste)
                ? .verifiedSuccess : .verificationFailed
        }

        func selectedText() -> String? {
            if let axSelected = selectedTextFromAXFocusedElement(),
                !axSelected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return axSelected
            }

            return selectedTextBySimulatedCopy()
        }

        func replaceSelectedText(
            _ text: String,
            into application: NSRunningApplication?,
            keepResultInClipboard: Bool
        ) async -> TextReplacementOutcome {
            guard !text.isEmpty else { return .injectionFailed(.verificationFailed) }

            if keepResultInClipboard {
                pasteboardRestoreCoordinator.discardPendingRestore()
            } else {
                pasteboardRestoreCoordinator.prepareForTemporaryOverride(on: pasteboard)
            }

            let clipboardWriteSucceeded = clipboardService.copy(
                text,
                transient: !keepResultInClipboard
            )
            guard clipboardWriteSucceeded else {
                if !keepResultInClipboard {
                    pasteboardRestoreCoordinator.restoreImmediatelyIfNeeded(on: pasteboard)
                }
                return .clipboardWriteFailed
            }

            let outcome = await pasteClipboard(into: application)

            guard outcome.didSucceed else {
                if !keepResultInClipboard {
                    pasteboardRestoreCoordinator.restoreImmediatelyIfNeeded(on: pasteboard)
                }
                return .injectionFailed(outcome)
            }

            guard !keepResultInClipboard else {
                return .replaced
            }

            pasteboardRestoreCoordinator.scheduleRestoreIfNeeded(on: pasteboard)

            return .replaced
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
                CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID()
            else {
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
                let selectedTextRef
            else {
                return nil
            }

            if let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
                return selectedText
            }

            if let selectedText = selectedTextRef as? NSAttributedString,
                !selectedText.string.isEmpty
            {
                return selectedText.string
            }

            return nil
        }

        private func selectedTextBySimulatedCopy() -> String? {
            guard accessState.canSimulateInput else { return nil }

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
                let keyDown = CGEvent(
                    keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                let keyUp = CGEvent(
                    keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            else {
                return false
            }

            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            return true
        }

        private func focusedElementSnapshot() -> FocusedElementSnapshot? {
            guard accessState.hasAccessibilityAccess,
                let focusedElement = focusedAXElement()
            else {
                return nil
            }

            return FocusedElementSnapshot(
                value: stringAttribute(kAXValueAttribute as CFString, from: focusedElement),
                selectedText: stringAttribute(
                    kAXSelectedTextAttribute as CFString, from: focusedElement),
                selectionRange: selectedRange(from: focusedElement),
                numberOfCharacters: numberOfCharacters(from: focusedElement)
            )
        }

        private func focusedAXElement() -> AXUIElement? {
            let systemWide = AXUIElementCreateSystemWide()
            var focusedElementRef: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(
                systemWide,
                kAXFocusedUIElementAttribute as CFString,
                &focusedElementRef
            )

            guard status == .success,
                let focusedElementRef,
                CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID()
            else {
                return nil
            }

            return unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        }

        private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
            var valueRef: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element, attribute, &valueRef)

            guard status == .success,
                let valueRef
            else {
                return nil
            }

            if let value = valueRef as? String, !value.isEmpty {
                return value
            }

            if let value = valueRef as? NSAttributedString, !value.string.isEmpty {
                return value.string
            }

            return nil
        }

        private func selectedRange(from element: AXUIElement) -> SelectionRange? {
            var rangeRef: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &rangeRef
            )

            guard status == .success,
                let rangeRef,
                CFGetTypeID(rangeRef) == AXValueGetTypeID()
            else {
                return nil
            }

            let axValue = unsafeBitCast(rangeRef, to: AXValue.self)
            guard AXValueGetType(axValue) == .cfRange else {
                return nil
            }

            var range = CFRange()
            guard AXValueGetValue(axValue, .cfRange, &range) else {
                return nil
            }

            return SelectionRange(location: range.location, length: range.length)
        }

        private func numberOfCharacters(from element: AXUIElement) -> Int? {
            var valueRef: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(
                element,
                kAXNumberOfCharactersAttribute as CFString,
                &valueRef
            )

            guard status == .success,
                let valueRef,
                let number = valueRef as? NSNumber
            else {
                return nil
            }

            return number.intValue
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
                let options =
                    [
                        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
                    ] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
        }

    }
#endif
