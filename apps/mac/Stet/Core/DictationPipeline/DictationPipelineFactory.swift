import Foundation

struct DictationPipeline: Sendable {
    let transcriptionService: any AudioFileTranscriptionService
    let promptProvider: (@Sendable () async -> String?)?
    let rewriteService: (any TextRewriteService)?
    let preferredSpellings: [String]
}

struct DictationPipelineFactory: Sendable {
    var relayAuthenticationContext: @Sendable () async -> RelayAuthenticationContext?
    var makeDirectTranscriptionService: @Sendable (
        OpenAIConfiguration,
        URLSession
    ) -> any AudioFileTranscriptionService
    var makeRelayTranscriptionService: @Sendable (
        RelayAuthenticationContext,
        URLSession,
        Bool,
        [String]
    ) -> any AudioFileTranscriptionService
    var makeRewriteService: @Sendable (OpenAIConfiguration, URLSession) -> any TextRewriteService

    static func live(
        relayAuthenticationContext: @escaping @Sendable () async -> RelayAuthenticationContext?
    ) -> Self {
        DictationPipelineFactory(
            relayAuthenticationContext: relayAuthenticationContext,
            makeDirectTranscriptionService: { configuration, session in
                OpenAITranscriptionService(
                    configuration: configuration,
                    session: session
                )
            },
            makeRelayTranscriptionService: {
                authentication,
                session,
                rewriteEnabled,
                preferredSpellings in
                RelayDictationTranscriptionService(
                    authentication: authentication,
                    session: session,
                    rewriteEnabled: rewriteEnabled,
                    preferredSpellings: preferredSpellings
                )
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
        let promptProvider: (@Sendable () async -> String?)?
        let rewriteService: (any TextRewriteService)?
        let preferredSpellings: [String]

        let networkSession = URLSession(configuration: .ephemeral)

        switch route {
        case .direct(let direct):
            transcriptionService = makeDirectTranscriptionService(
                direct.configuration,
                networkSession
            )
            promptProvider = nil
            preferredSpellings = direct.preferredSpellings

            if direct.rewriteEnabled {
                rewriteService = makeRewriteService(direct.configuration, networkSession)
            } else {
                rewriteService = nil
            }
        case .relay(let relay):
            transcriptionService = makeRelayTranscriptionService(
                relay.authentication,
                networkSession,
                relay.rewriteEnabled,
                relay.preferredSpellings
            )
            // Let ASR auto-detect language without an English-side prompt bias.
            promptProvider = nil
            rewriteService = nil
            preferredSpellings = relay.preferredSpellings
        }

        return DictationPipeline(
            transcriptionService: transcriptionService,
            promptProvider: promptProvider,
            rewriteService: rewriteService,
            preferredSpellings: preferredSpellings
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
