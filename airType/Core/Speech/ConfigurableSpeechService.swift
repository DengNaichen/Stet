import Foundation

actor ConfigurableSpeechService: SpeechService, AudioLevelStreaming {
    struct Dependencies: Sendable {
        var makeNetworkSession: @Sendable (NetworkProxySettings) -> URLSession
        var makeOpenAISpeechService: @Sendable (
            OpenAIConfiguration,
            URLSession,
            Locale,
            UInt32?,
            @escaping @Sendable () async -> String?
        ) async -> any SpeechService
        var makeRewriteService: @Sendable (OpenAIConfiguration, URLSession) -> any TextRewriteService

        static let live = Dependencies(
            makeNetworkSession: OpenAINetworkSession.makeSession,
            makeOpenAISpeechService: { configuration, session, locale, preferredInputDeviceID, promptProvider in
                await OpenAISpeechService(
                    transcriptionService: OpenAITranscriptionService(
                        configuration: configuration,
                        session: session
                    ),
                    locale: locale,
                    preferredInputDeviceID: preferredInputDeviceID,
                    transcriptionPromptProvider: promptProvider
                )
            },
            makeRewriteService: { configuration, session in
                OpenAIRewriteService(configuration: configuration, session: session)
            }
        )
    }

    private struct ActiveSession {
        let speechService: any SpeechService
        let rewriteService: (any TextRewriteService)?
        let preferredSpellings: [String]
        let contextInstructionsProvider: (@Sendable () async -> String?)
    }

    private let settingsStore: DictationSettingsStore
    private let locale: Locale
    private let captureContextStore: CaptureContextStore
    private let dependencies: Dependencies
    private let audioLevelBridge = AudioLevelBridge()

    private var activeSession: ActiveSession?
    private var audioLevelTask: Task<Void, Never>?

    init(
        settingsStore: DictationSettingsStore = DictationSettingsStore(),
        captureContextStore: CaptureContextStore = CaptureContextStore(),
        locale: Locale = .autoupdatingCurrent,
        dependencies: Dependencies = .live
    ) {
        self.settingsStore = settingsStore
        self.captureContextStore = captureContextStore
        self.locale = locale
        self.dependencies = dependencies
    }

    func makeAudioLevelStream() async -> AsyncStream<Double> {
        audioLevelBridge.makeStream()
    }

    func startRecording() async throws {
        guard activeSession == nil else {
            throw SpeechServiceError.alreadyRecording
        }

        let snapshot = settingsStore.loadSnapshot()
        let session = try await makeActiveSession(from: snapshot)

        do {
            try await session.speechService.startRecording()
            activeSession = session
            startAudioLevelForwarding(for: session)
        } catch {
            activeSession = nil
            stopAudioLevelForwarding()
            throw error
        }
    }

    func stopRecording() async throws -> String {
        guard let activeSession else {
            throw SpeechServiceError.notRecording
        }

        defer {
            self.activeSession = nil
            stopAudioLevelForwarding()
        }

        var transcript = try await activeSession.speechService.stopRecording()
        let contextInstructions = await activeSession.contextInstructionsProvider()

        if let rewriteService = activeSession.rewriteService {
            transcript = try await rewriteService.rewrite(
                .cleanup(
                    transcript,
                    preferredSpellings: activeSession.preferredSpellings,
                    contextInstructions: contextInstructions
                )
            )
        }

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            throw SpeechServiceError.emptyTranscription
        }

        return trimmedTranscript
    }

    func cancelRecording() async {
        guard let activeSession else { return }
        self.activeSession = nil
        stopAudioLevelForwarding()
        await activeSession.speechService.cancelRecording()
    }

    private func makeActiveSession(from snapshot: DictationSettingsSnapshot) async throws -> ActiveSession {
        let speechService: any SpeechService
        let networkSession = dependencies.makeNetworkSession(snapshot.proxySettings)
        let contextInstructionsProvider: @Sendable () async -> String? = { [captureContextStore] in
            guard snapshot.appBranchEnabled else { return nil }
            let contextSnapshot = await captureContextStore.snapshot()
            let resolution = AppBranchPromptResolver.resolve(
                in: snapshot.appBranchRules,
                snapshot: contextSnapshot,
                inputs: AppBranchPromptInputs(
                    rawTranscription: nil,
                    text: nil,
                    selectedText: nil,
                    targetLanguage: nil,
                    context: contextSnapshot.context
                )
            )

            if let match = resolution.match {
                AppLogger.info(
                    "Matched app branch rule '\(match.rule.name)' for bundleID=\(contextSnapshot.context.bundleID ?? "nil"), url=\(contextSnapshot.context.browserURL ?? "nil"), delivery=\(match.rule.promptDelivery.rawValue)",
                    category: .appBranch
                )
            }

            return resolution.renderedPrompt
        }

        guard let configuration = snapshot.openAIConfiguration else {
            throw OpenAIError.missingAPIKey
        }

        speechService = await dependencies.makeOpenAISpeechService(
            configuration,
            networkSession,
            locale,
            snapshot.preferredAudioInputDeviceID,
            { [captureContextStore] in
                guard snapshot.appBranchEnabled || !snapshot.personalDictionary.isEmpty else {
                    return nil
                }

                let contextSnapshot = await captureContextStore.snapshot()
                let resolution = snapshot.appBranchEnabled
                    ? AppBranchPromptResolver.resolve(
                        in: snapshot.appBranchRules,
                        snapshot: contextSnapshot,
                        inputs: AppBranchPromptInputs(
                            rawTranscription: nil,
                            text: nil,
                            selectedText: nil,
                            targetLanguage: nil,
                            context: contextSnapshot.context
                        )
                    )
                    : AppBranchPromptResolution(match: nil, renderedPrompt: nil)

                if let match = resolution.match {
                    AppLogger.info(
                        "Using app branch rule '\(match.rule.name)' in transcription prompt. delivery=\(match.rule.promptDelivery.rawValue)",
                        category: .appBranch
                    )
                }

                return Self.makeTranscriptionPrompt(
                    preferredSpellings: snapshot.personalDictionary,
                    contextInstructions: resolution.renderedPrompt
                )
            }
        )

        let rewriteService: (any TextRewriteService)?

        if snapshot.isRewriteEnabled {
            guard let configuration = snapshot.openAIConfiguration else {
                throw OpenAIError.missingAPIKey
            }

            rewriteService = dependencies.makeRewriteService(configuration, networkSession)
        } else {
            rewriteService = nil
        }

        return ActiveSession(
            speechService: speechService,
            rewriteService: rewriteService,
            preferredSpellings: snapshot.personalDictionary,
            contextInstructionsProvider: contextInstructionsProvider
        )
    }

    nonisolated static func makeTranscriptionPrompt(
        preferredSpellings: [String],
        contextInstructions: String?
    ) -> String? {
        var sections: [String] = []

        if !preferredSpellings.isEmpty {
            sections.append(
                "Use these exact spellings for names, brands, jargon, and technical terms when they are spoken or clearly intended: \(preferredSpellings.joined(separator: ", "))."
            )
        }

        if let contextInstructions = contextInstructions?.trimmingCharacters(in: .whitespacesAndNewlines),
           !contextInstructions.isEmpty {
            sections.append(
                "Apply these app-specific dictation instructions when they are relevant to the current app or page:\n\(contextInstructions)"
            )
        }

        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n")
    }

    private func startAudioLevelForwarding(for session: ActiveSession) {
        stopAudioLevelForwarding()

        guard let streamingService = session.speechService as? any AudioLevelStreaming else { return }
        let audioLevelBridge = self.audioLevelBridge

        audioLevelTask = Task {
            let stream = await streamingService.makeAudioLevelStream()
            for await level in stream {
                if Task.isCancelled {
                    break
                }

                audioLevelBridge.emit(level)
            }
        }
    }

    private func stopAudioLevelForwarding() {
        audioLevelTask?.cancel()
        audioLevelTask = nil
        audioLevelBridge.emit(0)
        audioLevelBridge.finish()
    }
}
