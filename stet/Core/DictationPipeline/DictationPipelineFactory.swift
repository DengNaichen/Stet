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
            URLSession
        ) -> any TextRewriteService
    var makeRewriteService: @Sendable (RewriteProviderConfiguration, URLSession) -> any TextRewriteService

    init(
        relayAuthenticationContext: @escaping @Sendable () async -> RelayAuthenticationContext?,
        makeLocalTranscriptionService: @escaping @Sendable () throws -> any AudioFileTranscriptionService,
        makeRelayTranscriptionService: @escaping @Sendable (
            RelayAuthenticationContext,
            URLSession,
            [String]
        ) -> any AudioFileTranscriptionService = { _, _, _ in
            preconditionFailure("Managed relay transcription is no longer used.")
        },
        makeRelayRewriteService: @escaping @Sendable (
            RelayAuthenticationContext,
            URLSession
        ) -> any TextRewriteService = { authentication, session in
            RelayTextRewriteService(authentication: authentication, session: session)
        },
        makeRewriteService: @escaping @Sendable (
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
                try LocalWhisperTranscriptionService(
                    modelManager: LocalWhisperModelManager()
                )
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
            makeRelayRewriteService: { authentication, session in
                RelayTextRewriteService(authentication: authentication, session: session)
            },
            makeRewriteService: { configuration, session in
                OpenAIRewriteService(configuration: configuration, session: session)
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
            promptProvider = nil
            preferredSpellings = direct.preferredSpellings
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
            promptProvider = nil
            if relay.rewriteEnabled {
                rewriteService = makeRelayRewriteService(
                    relay.authentication,
                    networkSession
                )
            } else {
                rewriteService = nil
            }
            rewriteAdditionalContext = snapshot.dictationLanguageMode.rewriteAdditionalContext
            preferredSpellings = relay.preferredSpellings
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

    nonisolated static func makeTranscriptionPrompt(
        preferredSpellings: [String]
    ) -> String? {
        var sections: [String] = []

        if !preferredSpellings.isEmpty {
            sections.append(
                "Use these exact spellings for names, brands, jargon, and technical terms when they are spoken or clearly intended: \(preferredSpellings.joined(separator: ", "))."
            )
        }

        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n")
    }
}
