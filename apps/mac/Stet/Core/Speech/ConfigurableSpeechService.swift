import Foundation

actor ConfigurableSpeechService: SpeechService, AudioLevelSource {
    struct Dependencies: Sendable {
        var relayAuthenticationContext: @Sendable () async -> RelayAuthenticationContext?
        var makeNetworkSession: @Sendable (NetworkProxySettings) -> URLSession
        var makeDirectSpeechService: @Sendable (
            OpenAIConfiguration,
            URLSession,
            Locale,
            @escaping @Sendable () async -> String?
        ) async -> any SpeechService
        var makeRelaySpeechService: @Sendable (
            RelayAuthenticationContext,
            URLSession,
            Locale,
            Bool,
            [String],
            @escaping @Sendable () async -> String?
        ) async -> any SpeechService
        var makeRewriteService: @Sendable (OpenAIConfiguration, URLSession) -> any TextRewriteService

        static let live = Dependencies(
            relayAuthenticationContext: {
                await MainActor.run {
                    SupabaseService.shared.relayAuthenticationContext
                }
            },
            makeNetworkSession: OpenAINetworkSession.makeSession,
            makeDirectSpeechService: { configuration, session, locale, promptProvider in
                await OpenAISpeechService(
                    transcriptionService: OpenAITranscriptionService(
                        configuration: configuration,
                        session: session
                    ),
                    locale: locale,
                    transcriptionPromptProvider: promptProvider
                )
            },
            makeRelaySpeechService: {
                authentication,
                session,
                locale,
                rewriteEnabled,
                preferredSpellings,
                promptProvider in
                await OpenAISpeechService(
                    transcriptionService: RelayDictationTranscriptionService(
                        authentication: authentication,
                        session: session,
                        rewriteEnabled: rewriteEnabled,
                        preferredSpellings: preferredSpellings
                    ),
                    locale: locale,
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
    }

    private let settingsStore: DictationSettingsStore
    private let locale: Locale
    private let dependencies: Dependencies
    private let audioLevelBridge = AudioLevelBridge()

    private var activeSession: ActiveSession?
    private var audioLevelTask: Task<Void, Never>?

    init(
        settingsStore: DictationSettingsStore = DictationSettingsStore(),
        locale: Locale = .autoupdatingCurrent,
        dependencies: Dependencies = .live
    ) {
        self.settingsStore = settingsStore
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

        if let rewriteService = activeSession.rewriteService {
            transcript = try await rewriteService.rewrite(
                .cleanup(
                    transcript,
                    preferredSpellings: activeSession.preferredSpellings
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
        let relayAuthentication = await dependencies.relayAuthenticationContext()
        let route = try DictationExecutionRouteResolver.resolve(
            snapshot: snapshot,
            relayAuthentication: relayAuthentication
        )
        let speechService: any SpeechService
        let rewriteService: (any TextRewriteService)?
        let preferredSpellings: [String]

        switch route {
        case .direct(let direct):
            let networkSession = dependencies.makeNetworkSession(direct.proxySettings)
            speechService = await dependencies.makeDirectSpeechService(
                direct.configuration,
                networkSession,
                locale,
                {
                    nil
                }
            )
            preferredSpellings = direct.preferredSpellings

            if direct.rewriteEnabled {
                rewriteService = dependencies.makeRewriteService(direct.configuration, networkSession)
            } else {
                rewriteService = nil
            }
        case .relay(let relay):
            let networkSession = dependencies.makeNetworkSession(relay.proxySettings)
            speechService = await dependencies.makeRelaySpeechService(
                relay.authentication,
                networkSession,
                locale,
                relay.rewriteEnabled,
                relay.preferredSpellings,
                {
                    Self.makeTranscriptionPrompt(preferredSpellings: relay.preferredSpellings)
                }
            )
            rewriteService = nil
            preferredSpellings = relay.preferredSpellings
        }

        return ActiveSession(
            speechService: speechService,
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

    private func startAudioLevelForwarding(for session: ActiveSession) {
        stopAudioLevelForwarding()

        guard let streamingService = session.speechService as? any AudioLevelSource else { return }
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
