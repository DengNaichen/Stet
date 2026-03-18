import Foundation

struct DictationPipeline: Sendable {
    let transcriptionService: any AudioFileTranscriptionService
    let promptProvider: (@Sendable () async -> String?)?
    let rewriteService: (any TextRewriteService)?
    let preferredSpellings: [String]
}

struct DictationPipelineFactory: Sendable {
    var relayAuthenticationContext: @Sendable () async -> RelayAuthenticationContext?
    var makeNetworkSession: @Sendable (NetworkProxySettings) -> URLSession
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

    static let live = DictationPipelineFactory(
        relayAuthenticationContext: {
            await MainActor.run {
                SupabaseService.shared.relayAuthenticationContext
            }
        },
        makeNetworkSession: OpenAINetworkSession.makeSession,
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

        switch route {
        case .direct(let direct):
            let networkSession = makeNetworkSession(direct.proxySettings)
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
            let networkSession = makeNetworkSession(relay.proxySettings)
            transcriptionService = makeRelayTranscriptionService(
                relay.authentication,
                networkSession,
                relay.rewriteEnabled,
                relay.preferredSpellings
            )
            promptProvider = {
                Self.makeTranscriptionPrompt(preferredSpellings: relay.preferredSpellings)
            }
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
