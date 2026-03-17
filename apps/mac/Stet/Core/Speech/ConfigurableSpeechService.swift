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
        let speechService: any SpeechService
        let networkSession = dependencies.makeNetworkSession(snapshot.proxySettings)

        guard let configuration = snapshot.openAIConfiguration else {
            throw OpenAIError.missingAPIKey(provider: snapshot.provider)
        }

        speechService = await dependencies.makeOpenAISpeechService(
            configuration,
            networkSession,
            locale,
            snapshot.preferredAudioInputDeviceID,
            {
                nil
            }
        )

        let rewriteService: (any TextRewriteService)?

        if snapshot.isRewriteEnabled {
            guard let configuration = snapshot.openAIConfiguration else {
                throw OpenAIError.missingAPIKey(provider: snapshot.provider)
            }

            rewriteService = dependencies.makeRewriteService(configuration, networkSession)
        } else {
            rewriteService = nil
        }

        return ActiveSession(
            speechService: speechService,
            rewriteService: rewriteService,
            preferredSpellings: snapshot.personalDictionary
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
