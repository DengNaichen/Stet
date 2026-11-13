#if os(macOS)
    import AppKit
    import ApplicationServices
    import StetAI
    import StetCore
    import StetRewrite

    /// Observes only the field captured immediately before our own dictation paste,
    /// settles at most once when editing ends, and evaluates candidate edits asynchronously.
    @MainActor
    final class MacCorrectionLearningService {
        enum Reading {
            case value(String)
            case unavailable
            case differentTarget
        }

        private let dictionary: DictionaryModel
        private let evaluatePair: @MainActor (CorrectionEditPair) async -> [String]
        private var observation: CorrectionObservation?
        private var read: (() -> Reading)?
        private var task: Task<Void, Never>?
        private var keyMonitor: Any?
        private var generation = UUID()
        private var pendingEvaluations: [UUID: Task<Void, Never>] = [:]

        init(
            dictionary: DictionaryModel = DictionaryModel(),
            evaluatePair: @escaping @MainActor (CorrectionEditPair) async -> [String] = { _ in [] }
        ) {
            self.dictionary = dictionary
            self.evaluatePair = evaluatePair
        }

        static func live(
            settingsStore: DictationSettingsStore,
            session: URLSession? = nil
        ) -> MacCorrectionLearningService {
            let learningSession: URLSession =
                session
                ?? {
                    let config = URLSessionConfiguration.ephemeral
                    config.timeoutIntervalForRequest = CloudGlossaryLearningService.defaultTimeoutInterval
                    config.timeoutIntervalForResource = CloudGlossaryLearningService.defaultTimeoutInterval
                    return URLSession(configuration: config)
                }()

            return MacCorrectionLearningService(dictionary: settingsStore.dictionaryModel) { pair in
                let snapshot = settingsStore.loadSnapshot()
                guard settingsStore.loadPersonalDictionaryEnabled(),
                    snapshot.isRewriteEnabled,
                    let rewriteConfiguration = snapshot.rewriteProviderConfiguration
                else {
                    return []
                }

                let service: any GlossaryLearningService
                switch rewriteConfiguration.backend {
                case .appleIntelligence:
                    if #available(macOS 26.0, *) {
                        service = AppleIntelligenceGlossaryLearningService()
                    } else {
                        return []
                    }
                case .remote, .google, .anthropic:
                    service = CloudGlossaryLearningService(
                        configuration: rewriteConfiguration,
                        session: learningSession
                    )
                }

                return (try? await service.extractTerms(from: pair)) ?? []
            }
        }

        /// Discards the active observation without evaluating (used when paste fails or cancels).
        func abort() {
            clearActiveObservation()
        }

        /// Settles any verified edit from the active observation and stops monitoring.
        func stop() {
            finishCurrentObservation(
                at: ProcessInfo.processInfo.systemUptime,
                triggeredByCompletionKey: false
            )
        }

        func finishCurrentObservation(
            at time: TimeInterval = ProcessInfo.processInfo.systemUptime,
            triggeredByCompletionKey: Bool = false
        ) {
            let activeObservation = observation
            let activeRead = read
            clearActiveObservation()

            guard dictionary.loadIsEnabled(), var activeObservation else { return }

            let currentField: String?
            if let activeRead, case .value(let value) = activeRead() {
                currentField = value
            } else {
                currentField = nil
            }

            let result = activeObservation.finish(
                currentField: currentField,
                triggeredByCompletionKey: triggeredByCompletionKey,
                at: time
            )
            if case .evaluate(let pair) = result {
                enqueueEvaluation(for: pair)
            }
        }

        func waitForPendingEvaluations() async {
            while let entry = pendingEvaluations.first {
                await entry.value.value
                pendingEvaluations.removeValue(forKey: entry.key)
            }
        }

        func prepare(inserted: String, application: NSRunningApplication?) {
            finishCurrentObservation()
            guard dictionary.loadIsEnabled(),
                AXIsProcessTrusted(),
                let app = application ?? NSWorkspace.shared.frontmostApplication,
                app.bundleIdentifier != Bundle.main.bundleIdentifier,
                NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
            else { return }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            // Keep each AX read bounded if a target app is hung.
            AXUIElementSetMessagingTimeout(appElement, 0.1)
            guard let field = Self.focusedElement(in: appElement) else { return }
            AXUIElementSetMessagingTimeout(field, 0.1)

            guard Self.string(kAXSubroleAttribute, from: field) != kAXSecureTextFieldSubrole,
                let before = Self.text(in: field),
                let selection = Self.selection(in: field)
            else { return }

            let now = ProcessInfo.processInfo.systemUptime
            guard
                let observation = CorrectionObservation(
                    before: before,
                    selection: selection,
                    inserted: inserted,
                    startedAt: now
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
            finishCurrentObservation()
            self.observation = observation
            self.read = read
        }

        func start() {
            guard observation != nil else { return }
            let id = generation
            let deadline = ProcessInfo.processInfo.systemUptime + CorrectionObservation.observationWindow
            task = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.generation == id else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    guard now <= deadline else {
                        self.finishCurrentObservation(at: now, triggeredByCompletionKey: false)
                        return
                    }
                    self.sample(at: now)
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                }
            }
            // Only completion keys trigger final settlement; typed characters are never retained.
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard [36, 76, 48].contains(event.keyCode), !event.modifierFlags.contains(.shift) else { return }
                MainActor.assumeIsolated { [weak self] in
                    guard let self, self.generation == id else { return }
                    self.finishCurrentObservation(
                        at: ProcessInfo.processInfo.systemUptime,
                        triggeredByCompletionKey: true
                    )
                }
            }
        }

        func sample(at time: TimeInterval) {
            guard dictionary.loadIsEnabled(), var activeObservation = observation, let read else {
                clearActiveObservation()
                return
            }

            switch read() {
            case .differentTarget:
                finishCurrentObservation(at: time, triggeredByCompletionKey: false)
            case .unavailable:
                break
            case .value(let field):
                let result = activeObservation.sample(field, at: time)
                self.observation = activeObservation
                switch result {
                case .waiting:
                    break
                case .evaluate(let pair):
                    clearActiveObservation()
                    enqueueEvaluation(for: pair)
                case .finished:
                    clearActiveObservation()
                }
            }
        }

        private func clearActiveObservation() {
            generation = UUID()
            task?.cancel()
            task = nil
            observation = nil
            read = nil
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }

        private func enqueueEvaluation(for pair: CorrectionEditPair) {
            let evaluationID = UUID()
            let evaluationTask = Task { @MainActor [weak self] in
                defer { self?.pendingEvaluations.removeValue(forKey: evaluationID) }
                guard let self, self.dictionary.loadIsEnabled() else { return }
                let terms = await self.evaluatePair(pair)
                guard self.dictionary.loadIsEnabled(), !terms.isEmpty else { return }
                self.dictionary.addAutomaticEntries(terms)
            }
            pendingEvaluations[evaluationID] = evaluationTask
        }

        private static func string(_ attribute: String, from element: AXUIElement) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                let value
            else { return nil }
            if let text = value as? String { return text }
            if let attributed = value as? NSAttributedString { return attributed.string }
            return nil
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
                ) == .success,
                let value
            else { return nil }
            if let text = value as? String { return text }
            if let attributed = value as? NSAttributedString { return attributed.string }
            return nil
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
