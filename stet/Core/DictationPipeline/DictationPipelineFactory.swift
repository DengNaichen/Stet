import Foundation

struct DictationPipeline: Sendable {
    let transcriptionService: any AudioFileTranscriptionService
    let transcriptionLanguageCode: String?
    let promptProvider: (@Sendable () async -> String?)?
    let rewriteService: (any TextRewriteService)?
    let rewriteAdditionalContext: String?
    let preferredSpellings: [String]
    let usesAudienceAwareLocalPrompts: Bool
}

struct DictationPipelineFactory: Sendable {
    var relayAuthenticationContext: @Sendable () async -> RelayAuthenticationContext?
    var makeLocalTranscriptionService: @Sendable () throws -> any AudioFileTranscriptionService
    var makeRelayTranscriptionService:
        @Sendable (
            RelayAuthenticationContext,
            URLSession,
            [String]
        ) -> any AudioFileTranscriptionService
    var makeRelayRewriteService:
        @Sendable (
            RelayAuthenticationContext,
            @escaping @Sendable () async -> RelayAuthenticationContext?,
            URLSession
        ) -> any TextRewriteService
    var makeRewriteService: @Sendable (RewriteProviderConfiguration, URLSession) -> any TextRewriteService

    init(
        relayAuthenticationContext: @escaping @Sendable () async -> RelayAuthenticationContext?,
        makeLocalTranscriptionService: @escaping @Sendable () throws -> any AudioFileTranscriptionService,
        makeRelayTranscriptionService:
            @escaping @Sendable (
                RelayAuthenticationContext,
                URLSession,
                [String]
            ) -> any AudioFileTranscriptionService = { _, _, _ in
                preconditionFailure("Managed relay transcription is no longer used.")
            },
        makeRelayRewriteService:
            @escaping @Sendable (
                RelayAuthenticationContext,
                @escaping @Sendable () async -> RelayAuthenticationContext?,
                URLSession
            ) -> any TextRewriteService = { authentication, authenticationProvider, session in
                RelayTextRewriteService(
                    authentication: authentication,
                    authenticationProvider: authenticationProvider,
                    session: session
                )
            },
        makeRewriteService:
            @escaping @Sendable (
                RewriteProviderConfiguration,
                URLSession
            ) -> any TextRewriteService
    ) {
        self.relayAuthenticationContext = relayAuthenticationContext
        self.makeLocalTranscriptionService = makeLocalTranscriptionService
        self.makeRelayTranscriptionService = makeRelayTranscriptionService
        self.makeRelayRewriteService = makeRelayRewriteService
        self.makeRewriteService = makeRewriteService
    }

    static func live(
        relayAuthenticationContext: @escaping @Sendable () async -> RelayAuthenticationContext?
    ) -> Self {
        DictationPipelineFactory(
            relayAuthenticationContext: relayAuthenticationContext,
            makeLocalTranscriptionService: {
                try Self.makeLiveLocalTranscriptionService()
            },
            makeRelayTranscriptionService: {
                authentication,
                session,
                preferredSpellings in
                RelayDictationTranscriptionService(
                    authentication: authentication,
                    session: session,
                    preferredSpellings: preferredSpellings,
                    audienceProvider: { AppBranchMonitor.shared.currentApp?.audience ?? .ai }
                )
            },
            makeRelayRewriteService: { authentication, authenticationProvider, session in
                RelayTextRewriteService(
                    authentication: authentication,
                    authenticationProvider: authenticationProvider,
                    session: session
                )
            },
            makeRewriteService: { configuration, session in
                if configuration.provider == .appleIntelligence {
                    return AppleIntelligenceRewriteService()
                }
                return OpenAIRewriteService(configuration: configuration, session: session)
            }
        )
    }

    func makePipeline(
        from snapshot: DictationSettingsSnapshot
    ) async throws -> DictationPipeline {
        let relayAuthentication = await relayAuthenticationContext()
        let route = try DictationExecutionRouteResolver.resolve(
            snapshot: snapshot,
            relayAuthentication: relayAuthentication
        )
        let transcriptionService: any AudioFileTranscriptionService
        let transcriptionLanguageCode: String?
        let promptProvider: (@Sendable () async -> String?)?
        let rewriteService: (any TextRewriteService)?
        let rewriteAdditionalContext: String?
        let preferredSpellings: [String]
        let usesAudienceAwareLocalPrompts: Bool

        let networkSession = URLSession(configuration: .ephemeral)

        switch route {
        case .direct(let direct):
            transcriptionService = try makeLocalTranscriptionService()
            transcriptionLanguageCode = snapshot.dictationLanguageMode.transcriptionLanguageCode
            preferredSpellings = direct.preferredSpellings
            promptProvider = Self.makePromptProvider(preferredSpellings: preferredSpellings)
            rewriteAdditionalContext = snapshot.dictationLanguageMode.rewriteAdditionalContext
            usesAudienceAwareLocalPrompts = snapshot.executionMode == .byok

            if direct.rewriteEnabled, let rewriteConfiguration = direct.rewriteConfiguration {
                rewriteService = makeRewriteService(rewriteConfiguration, networkSession)
            } else {
                rewriteService = nil
            }
        case .relay(let relay):
            transcriptionService = try makeLocalTranscriptionService()
            transcriptionLanguageCode = snapshot.dictationLanguageMode.transcriptionLanguageCode
            if relay.rewriteEnabled {
                rewriteService = makeRelayRewriteService(
                    relay.authentication,
                    relayAuthenticationContext,
                    networkSession
                )
            } else {
                rewriteService = nil
            }
            rewriteAdditionalContext = snapshot.dictationLanguageMode.rewriteAdditionalContext
            preferredSpellings = relay.preferredSpellings
            promptProvider = Self.makePromptProvider(preferredSpellings: preferredSpellings)
            usesAudienceAwareLocalPrompts = true
        }

        return DictationPipeline(
            transcriptionService: transcriptionService,
            transcriptionLanguageCode: transcriptionLanguageCode,
            promptProvider: promptProvider,
            rewriteService: rewriteService,
            rewriteAdditionalContext: rewriteAdditionalContext,
            preferredSpellings: preferredSpellings,
            usesAudienceAwareLocalPrompts: usesAudienceAwareLocalPrompts
        )
    }

    /// Picks which local-engine implementation to instantiate based on the
    /// user's `localTranscriptionEngine` preference. Whisper is the default and
    /// kept for the case where the Parakeet model isn't downloaded yet — we
    /// fall back to whisper rather than throwing so dictation never hard-fails
    /// because of a misconfigured picker.
    nonisolated static func makeLiveLocalTranscriptionService() throws -> any AudioFileTranscriptionService {
        #if os(macOS)
            let engine = LocalTranscriptionEngine.current()
            AppLogger.info(
                "DictationPipelineFactory selected local engine=\(engine.rawValue)",
                category: .dictation
            )

            switch engine {
            case .parakeet:
                do {
                    return try FluidAudioTranscriptionService()
                } catch {
                    AppLogger.warning(
                        "Parakeet engine unavailable (\(error.localizedDescription)); falling back to local whisper.",
                        category: .dictation
                    )
                    return try LocalWhisperTranscriptionService(modelManager: LocalWhisperModelManager())
                }
            case .whisper:
                return try LocalWhisperTranscriptionService(modelManager: LocalWhisperModelManager())
            }
        #else
            return try LocalWhisperTranscriptionService(modelManager: LocalWhisperModelManager())
        #endif
    }

    nonisolated static func makeTranscriptionPrompt(
        preferredSpellings: [String]
    ) -> String? {
        var sections: [String] = []

        if !preferredSpellings.isEmpty {
            sections.append(
                preferredSpellings.joined(separator: ", ")
            )
        }

        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n")
    }

    private nonisolated static func makePromptProvider(
        preferredSpellings: [String]
    ) -> (@Sendable () async -> String?)? {
        guard let prompt = makeTranscriptionPrompt(preferredSpellings: preferredSpellings) else {
            return nil
        }

        return { prompt }
    }
}
