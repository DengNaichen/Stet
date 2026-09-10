#if os(macOS)
    import AppKit
    import ApplicationServices
    import StetCore

    /// Reads only the field captured immediately before our own paste command.
    /// No global text/key logging, clipboard reads during observation, or AX writes.
    @MainActor
    final class MacCorrectionLearningService {
        enum Reading {
            case value(String)
            case unavailable
            case differentTarget
        }

        private let dictionary: DictionaryModel
        private var observation: CorrectionObservation?
        private var read: (() -> Reading)?
        private var task: Task<Void, Never>?
        private var keyMonitor: Any?
        private var generation = UUID()

        init(dictionary: DictionaryModel = DictionaryModel()) { self.dictionary = dictionary }

        func stop() {
            generation = UUID()
            task?.cancel()
            task = nil
            observation = nil
            read = nil
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }

        func prepare(inserted: String, application: NSRunningApplication?) {
            stop()
            guard dictionary.loadIsEnabled(), AXIsProcessTrusted(),
                let app = application ?? NSWorkspace.shared.frontmostApplication,
                app.bundleIdentifier != Bundle.main.bundleIdentifier,
                NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
            else { return }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            // Keep each AX read bounded if a target app is hung.
            AXUIElementSetMessagingTimeout(appElement, 0.1)
            guard let field = Self.focusedElement(in: appElement),
                Self.string(kAXSubroleAttribute, from: field) != kAXSecureTextFieldSubrole,
                let role = Self.string(kAXRoleAttribute, from: field),
                [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
                let before = Self.text(in: field),
                let selection = Self.selection(in: field)
            else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard
                let observation = CorrectionObservation(
                    before: before, selection: selection, inserted: inserted, startedAt: now
                )
            else { return }
            prepare(observation: observation) {
                guard !app.isTerminated,
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
                else { return .differentTarget }
                guard let focused = Self.focusedElement(in: appElement) else { return .unavailable }
                guard CFEqual(focused, field) else { return .differentTarget }
                guard let value = Self.text(in: field) else { return .unavailable }
                return .value(value)
            }
        }

        // Explicit seam for the AX adapter: callers supply only the captured field.
        func prepare(observation: CorrectionObservation, read: @escaping () -> Reading) {
            stop()
            self.observation = observation
            self.read = read
        }

        func start() {
            guard observation != nil else { return }
            let id = generation
            let deadline = ProcessInfo.processInfo.systemUptime + 30
            task = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.generation == id else { return }
                    guard ProcessInfo.processInfo.systemUptime <= deadline else { self.stop(); return }
                    self.sample(at: ProcessInfo.processInfo.systemUptime)
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                }
            }
            // Only completion keys trigger a final sample; characters are never retained.
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard [36, 76, 48].contains(event.keyCode), !event.modifierFlags.contains(.shift) else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == id else { return }
                    self.sample(at: ProcessInfo.processInfo.systemUptime, finishing: true)
                }
            }
        }

        func sample(at time: TimeInterval, finishing: Bool = false) {
            guard dictionary.loadIsEnabled(), var observation, let read else { stop(); return }
            switch read() {
            case .differentTarget:
                stop()
            case .unavailable:
                // Never use stale text as a substitute for the final field contents.
                if finishing { stop() }
            case .value(let field):
                let result = observation.sample(field, at: time, finishing: finishing)
                self.observation = observation
                switch result {
                case .learn(let corrections): dictionary.addAutomaticEntries(corrections.map(\.replacement))
                case .finished: stop()
                case .waiting: break
                }
                if finishing { stop() }
            }
        }

        private static func string(_ attribute: String, from element: AXUIElement) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
            return value as? String
        }

        private static func text(in element: AXUIElement) -> String? {
            if let value = string(kAXValueAttribute, from: element) { return value }
            // Some editors expose ranged text instead of AXValue. This is still
            // a read of the same captured element, never a simulated Select All/Copy.
            var countValue: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &countValue)
                    == .success,
                let count = (countValue as? NSNumber)?.intValue, count >= 0, count <= 96_000
            else { return nil }
            var range = CFRange(location: 0, length: count)
            guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
            var value: CFTypeRef?
            guard
                AXUIElementCopyParameterizedAttributeValue(
                    element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value
                ) == .success
            else { return nil }
            return value as? String
        }

        private static func focusedElement(in app: AXUIElement) -> AXUIElement? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
                let value, CFGetTypeID(value) == AXUIElementGetTypeID()
            else { return nil }
            return unsafeBitCast(value, to: AXUIElement.self)
        }

        private static func selection(in element: AXUIElement) -> NSRange? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
                let value, CFGetTypeID(value) == AXValueGetTypeID()
            else { return nil }
            let axValue = unsafeBitCast(value, to: AXValue.self)
            var range = CFRange()
            guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range),
                range.location >= 0, range.length >= 0
            else { return nil }
            return NSRange(location: range.location, length: range.length)
        }
    }
#endif
