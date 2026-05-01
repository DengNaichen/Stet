#if os(macOS)
    import AppKit
    import ApplicationServices
    import Foundation
    import os

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
        case eventPostedVerificationUnavailableInTextInput
        case eventPostedVerificationUnavailable
        case verificationFailed
        case eventPostFailed

        var didSucceed: Bool {
            switch self {
            case .verifiedSuccess:
                return true
            case .eventPostedVerificationUnavailableInTextInput,
                .eventPostedVerificationUnavailable,
                .verificationFailed,
                .eventPostFailed:
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
        private enum VerificationBaseline {
            case verifiable(FocusedElementSnapshot)
            case likelyTextInput(FocusedElementSnapshot)
            case unavailable
        }

        private enum KeyCode {
            static let copy: CGKeyCode = 8
            static let paste: CGKeyCode = 9
        }

        struct SelectionRange: Equatable {
            let location: Int
            let length: Int
        }

        struct FocusedElementSnapshot: Equatable {
            let value: String?
            let selectedText: String?
            let selectionRange: SelectionRange?
            let numberOfCharacters: Int?
            let role: String?
            let isEditable: Bool?

            var canVerifyPaste: Bool {
                value != nil || selectedText != nil || selectionRange != nil || numberOfCharacters != nil
            }

            var likelyAcceptsPastedText: Bool {
                if canVerifyPaste || isEditable == true {
                    return true
                }

                switch role {
                case "AXTextArea",
                    "AXTextField",
                    "AXSearchField",
                    "AXComboBox",
                    "AXTextView":
                    return true
                case "AXWebArea":
                    return isEditable == true
                default:
                    return false
                }
            }

            var traceSummary: String {
                let valueLength = value.map { String($0.count) } ?? "nil"
                let selectedTextLength = selectedText.map { String($0.count) } ?? "nil"
                let selectionRangeSummary =
                    selectionRange.map { "\($0.location):\($0.length)" } ?? "nil"
                let characterCount = numberOfCharacters.map(String.init) ?? "nil"
                let roleSummary = role ?? "nil"
                let editableSummary = isEditable.map(String.init) ?? "nil"

                return
                    "valueLen=\(valueLength) selectedLen=\(selectedTextLength) range=\(selectionRangeSummary) chars=\(characterCount) role=\(roleSummary) editable=\(editableSummary)"
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
        private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet", category: "TextInjection")

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
            let state = accessState
            let needsVerificationAccess = !state.hasAccessibilityAccess

            guard
                (!state.canSimulateInput || needsVerificationAccess),
                !didPromptForMissingAccessThisSession
            else {
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
            await performPasteClipboard(
                into: application,
                accessState: accessState,
                activateApplication: { application in
                    _ = application.activate()
                },
                snapshotProvider: { [weak self] in
                    self?.focusedElementSnapshot()
                },
                simulatePasteCommand: { [weak self] in
                    self?.simulateCommandKey(KeyCode.paste) ?? false
                },
                sleep: { duration in
                    try? await Task.sleep(for: duration)
                }
            )
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

        func performPasteClipboard(
            into application: NSRunningApplication?,
            accessState: TextInjectionAccessState,
            activateApplication: @MainActor (NSRunningApplication) -> Void,
            snapshotProvider: @MainActor () -> FocusedElementSnapshot?,
            simulatePasteCommand: @MainActor () -> Bool,
            sleep: @escaping @Sendable (Duration) async -> Void,
            activationDelay: Duration = .milliseconds(180),
            // Tuned for performance: 60ms -> 15ms
            prePasteDelay: Duration = .milliseconds(15),
            verificationBaselinePollInterval: Duration = .milliseconds(60),
            verificationBaselineAttempts: Int = 1,
            // Tuned for performance: 120ms -> 30ms
            verificationPollInterval: Duration = .milliseconds(30),
            verificationAttempts: Int = 1
        ) async -> TextInjectionOutcome {
            let traceID = makeTextInjectionTraceID()
            emitTextInjectionTrace(
                traceID,
                stage: "begin",
                details:
                    "target=\(applicationSummary(application)) frontmost=\(frontmostApplicationSummary()) accessibility=\(accessState.hasAccessibilityAccess) postEvent=\(accessState.hasPostEventAccess)"
            )

            guard accessState.canSimulateInput else {
                emitTextInjectionTrace(
                    traceID,
                    stage: "outcome",
                    details: "outcome=\(outcomeLabel(.eventPostFailed)) reason=no_input_access"
                )
                return .eventPostFailed
            }

            if let application,
                !application.isTerminated,
                application.bundleIdentifier != Bundle.main.bundleIdentifier
            {
                emitTextInjectionTrace(
                    traceID,
                    stage: "activate_target",
                    details:
                        "target=\(applicationSummary(application)) frontmostBefore=\(frontmostApplicationSummary()) delayMs=\(durationMilliseconds(activationDelay))"
                )
                activateApplication(application)
                await sleep(activationDelay)
                emitTextInjectionTrace(
                    traceID,
                    stage: "activate_target_settled",
                    details: "frontmostAfter=\(frontmostApplicationSummary())"
                )
            }

            await sleep(prePasteDelay)
            emitTextInjectionTrace(
                traceID,
                stage: "baseline_capture_start",
                details:
                    "attempts=\(max(1, verificationBaselineAttempts)) pollMs=\(durationMilliseconds(verificationBaselinePollInterval)) frontmost=\(frontmostApplicationSummary())"
            )
            let snapshotBeforePaste = await captureVerificationBaseline(
                snapshotProvider: snapshotProvider,
                sleep: sleep,
                pollInterval: verificationBaselinePollInterval,
                attempts: verificationBaselineAttempts,
                traceID: traceID
            )

            let pasteCommandPosted = simulatePasteCommand()
            emitTextInjectionTrace(
                traceID,
                stage: "paste_command",
                details:
                    "success=\(pasteCommandPosted) baseline=\(verificationBaselineSummary(snapshotBeforePaste)) frontmost=\(frontmostApplicationSummary())"
            )

            guard pasteCommandPosted else {
                emitTextInjectionTrace(
                    traceID,
                    stage: "outcome",
                    details: "outcome=\(outcomeLabel(.eventPostFailed))"
                )
                return .eventPostFailed
            }

            switch snapshotBeforePaste {
            case .verifiable(let snapshot):
                return await verifyPasteOutcome(
                    comparedTo: snapshot,
                    snapshotProvider: snapshotProvider,
                    sleep: sleep,
                    pollInterval: verificationPollInterval,
                    attempts: verificationAttempts,
                    traceID: traceID
                )

            case .likelyTextInput(let snapshot):
                emitTextInjectionTrace(
                    traceID,
                    stage: "outcome",
                    details:
                        "outcome=\(outcomeLabel(.eventPostedVerificationUnavailableInTextInput)) reason=missing_verifiable_baseline_likely_text_input baseline=\(snapshot.traceSummary) frontmost=\(frontmostApplicationSummary())"
                )
                return .eventPostedVerificationUnavailableInTextInput

            case .unavailable:
                emitTextInjectionTrace(
                    traceID,
                    stage: "outcome",
                    details:
                        "outcome=\(outcomeLabel(.eventPostedVerificationUnavailable)) reason=missing_verifiable_baseline frontmost=\(frontmostApplicationSummary())"
                )
                return .eventPostedVerificationUnavailable
            }
        }

        func verifyPasteOutcome(
            comparedTo snapshotBeforePaste: FocusedElementSnapshot,
            snapshotProvider: @MainActor () -> FocusedElementSnapshot?,
            sleep: @escaping @Sendable (Duration) async -> Void,
            pollInterval: Duration = .milliseconds(120),
            attempts: Int = 4,
            traceID: String? = nil
        ) async -> TextInjectionOutcome {
            guard snapshotBeforePaste.canVerifyPaste else {
                emitTextInjectionTrace(
                    traceID,
                    stage: "outcome",
                    details:
                        "outcome=\(outcomeLabel(.eventPostedVerificationUnavailable)) reason=baseline_not_verifiable"
                )
                return .eventPostedVerificationUnavailable
            }

            let retryCount = max(1, attempts)
            var observedVerifiableSnapshot = false
            emitTextInjectionTrace(
                traceID,
                stage: "verification_start",
                details:
                    "attempts=\(retryCount) pollMs=\(durationMilliseconds(pollInterval)) baseline=\(snapshotBeforePaste.traceSummary)"
            )

            for attempt in 0..<retryCount {
                await sleep(pollInterval)

                guard let snapshotAfterPaste = snapshotProvider() else {
                    emitTextInjectionTrace(
                        traceID,
                        stage: "verification_poll",
                        details:
                            "attempt=\(attempt + 1)/\(retryCount) snapshot=nil frontmost=\(frontmostApplicationSummary())"
                    )
                    continue
                }

                observedVerifiableSnapshot =
                    observedVerifiableSnapshot || snapshotAfterPaste.canVerifyPaste
                let didMutate = snapshotAfterPaste.indicatesMutation(comparedTo: snapshotBeforePaste)

                emitTextInjectionTrace(
                    traceID,
                    stage: "verification_poll",
                    details:
                        "attempt=\(attempt + 1)/\(retryCount) snapshot=\(snapshotAfterPaste.traceSummary) verifiable=\(snapshotAfterPaste.canVerifyPaste) mutated=\(didMutate) frontmost=\(frontmostApplicationSummary())"
                )

                if didMutate {
                    emitTextInjectionTrace(
                        traceID,
                        stage: "outcome",
                        details:
                            "outcome=\(outcomeLabel(.verifiedSuccess)) attempt=\(attempt + 1)"
                    )
                    return .verifiedSuccess
                }
            }

            let outcome: TextInjectionOutcome =
                observedVerifiableSnapshot
                ? .verificationFailed
                : .eventPostedVerificationUnavailableInTextInput
            emitTextInjectionTrace(
                traceID,
                stage: "outcome",
                details:
                    "outcome=\(outcomeLabel(outcome)) observedVerifiableSnapshot=\(observedVerifiableSnapshot)"
            )
            return outcome
        }

        private func captureVerificationBaseline(
            snapshotProvider: @MainActor () -> FocusedElementSnapshot?,
            sleep: @escaping @Sendable (Duration) async -> Void,
            pollInterval: Duration,
            attempts: Int,
            traceID: String? = nil
        ) async -> VerificationBaseline {
            let retryCount = max(1, attempts)
            var likelyTextInputSnapshot: FocusedElementSnapshot?

            for attempt in 0..<retryCount {
                let snapshot = snapshotProvider()
                emitTextInjectionTrace(
                    traceID,
                    stage: "baseline_capture_attempt",
                    details:
                        "attempt=\(attempt + 1)/\(retryCount) snapshot=\(snapshot?.traceSummary ?? "nil") frontmost=\(frontmostApplicationSummary())"
                )

                if let snapshot, snapshot.canVerifyPaste {
                    return .verifiable(snapshot)
                }

                if let snapshot, snapshot.likelyAcceptsPastedText {
                    likelyTextInputSnapshot = snapshot
                }

                guard attempt + 1 < retryCount else {
                    break
                }

                await sleep(pollInterval)
            }

            if let likelyTextInputSnapshot {
                return .likelyTextInput(likelyTextInputSnapshot)
            }

            return .unavailable
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
                numberOfCharacters: numberOfCharacters(from: focusedElement),
                role: stringAttribute(kAXRoleAttribute as CFString, from: focusedElement),
                isEditable: boolAttribute("AXEditable" as CFString, from: focusedElement)
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

        private func boolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool? {
            var valueRef: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element, attribute, &valueRef)

            guard status == .success, let number = valueRef as? NSNumber else {
                return nil
            }

            return number.boolValue
        }

        private func requestMissingAccesses(trigger: String) {
            let state = accessState
            logger.info(
                "Requesting text injection permissions. trigger=\(trigger), accessibility=\(state.hasAccessibilityAccess), postEvent=\(state.hasPostEventAccess)"
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

        private func makeTextInjectionTraceID() -> String {
            String(UUID().uuidString.prefix(8))
        }

        private func emitTextInjectionTrace(_ traceID: String?, stage: String, details: String? = nil) {
            guard let traceID else { return }
            let detailsSuffix = details.map { " \($0)" } ?? ""
            logger.info(
                "TextInjectionTrace id=\(traceID) stage=\(stage)\(detailsSuffix)"
            )
        }

        private func applicationSummary(_ application: NSRunningApplication?) -> String {
            guard let application else { return "nil" }
            let bundleIdentifier = application.bundleIdentifier ?? "unknown"
            return "\(bundleIdentifier)(pid=\(application.processIdentifier))"
        }

        private func frontmostApplicationSummary() -> String {
            applicationSummary(NSWorkspace.shared.frontmostApplication)
        }

        private func outcomeLabel(_ outcome: TextInjectionOutcome) -> String {
            switch outcome {
            case .verifiedSuccess:
                return "verifiedSuccess"
            case .eventPostedVerificationUnavailableInTextInput:
                return "eventPostedVerificationUnavailableInTextInput"
            case .eventPostedVerificationUnavailable:
                return "eventPostedVerificationUnavailable"
            case .verificationFailed:
                return "verificationFailed"
            case .eventPostFailed:
                return "eventPostFailed"
            }
        }

        private func verificationBaselineSummary(_ baseline: VerificationBaseline) -> String {
            switch baseline {
            case .verifiable(let snapshot):
                return "verifiable:\(snapshot.traceSummary)"
            case .likelyTextInput(let snapshot):
                return "likelyTextInput:\(snapshot.traceSummary)"
            case .unavailable:
                return "unavailable"
            }
        }

        private func durationMilliseconds(_ duration: Duration) -> String {
            let components = duration.components
            let milliseconds =
                (Double(components.seconds) * 1_000)
                + (Double(components.attoseconds) / 1_000_000_000_000_000)
            return String(format: "%.1f", milliseconds)
        }

    }
#endif
