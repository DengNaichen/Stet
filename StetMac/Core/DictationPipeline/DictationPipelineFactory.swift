import Foundation
import StetAI
import StetCore
import StetRewrite
import os

struct DictationPipeline: Sendable {
    let transcriptionService: any AudioFileTranscriptionService
    let transcriptionLanguageCode: String?
    let promptProvider: (@Sendable () async -> String?)?
    let rewriteService: (any TextRewriteService)?
    let rewriteProvider: DictationProvider?
    let preferredSpellings: [String]
    let usesAudienceAwareLocalPrompts: Bool
}

struct DictationPipelineFactory: Sendable {
    var makeLocalTranscriptionService: @Sendable () throws -> any AudioFileTranscriptionService
    var makeRewriteService: @Sendable (RewriteProviderConfiguration, URLSession) -> any TextRewriteService

    init(
        makeLocalTranscriptionService: @escaping @Sendable () throws -> any AudioFileTranscriptionService,
        makeRewriteService:
            @escaping @Sendable (
                RewriteProviderConfiguration,
                URLSession
            ) -> any TextRewriteService
    ) {
        self.makeLocalTranscriptionService = makeLocalTranscriptionService
        self.makeRewriteService = makeRewriteService
    }

    static func live(configuration: any ModelStorageConfiguration = UserDefaultsModelStorage()) -> Self {
        DictationPipelineFactory(
            makeLocalTranscriptionService: {
                try Self.makeLiveLocalTranscriptionService(configuration: configuration)
            },
            makeRewriteService: { configuration, session in
                switch configuration.backend {
                case .appleIntelligence:
                    if #available(macOS 26.0, *) {
                        return AppleIntelligenceRewriteService()
                    } else {
                        return UnavailableRewriteService(message: "Apple Intelligence requires macOS 26.0 or newer.")
                    }
                case .google(let apiKey):
                    return GoogleRewriteService(apiKey: apiKey, model: configuration.model, session: session)
                case .anthropic(let apiKey):
                    return AnthropicRewriteService(apiKey: apiKey, model: configuration.model, session: session)
                case .remote:
                    return OpenAIRewriteService(configuration: configuration, session: session)
                }
            }
        )
    }

    func makePipeline(
        from snapshot: DictationSettingsSnapshot
    ) async throws -> DictationPipeline {
        let route = try DictationExecutionRouteResolver.resolve(
            snapshot: snapshot
        )
        let transcriptionService: any AudioFileTranscriptionService
        let transcriptionLanguageCode: String?
        let promptProvider: (@Sendable () async -> String?)?
        let rewriteService: (any TextRewriteService)?
        let rewriteProvider: DictationProvider?
        let preferredSpellings: [String]
        let usesAudienceAwareLocalPrompts: Bool

        let networkSession = URLSession(configuration: .ephemeral)

        switch route {
        case .direct(let direct):
            transcriptionService = try makeLocalTranscriptionService()

            transcriptionLanguageCode = snapshot.transcriptionPrimaryLanguage
            preferredSpellings = direct.preferredSpellings
            promptProvider = Self.makePromptProvider(preferredSpellings: preferredSpellings)
            usesAudienceAwareLocalPrompts = true

            if direct.rewriteEnabled, let rewriteConfiguration = direct.rewriteConfiguration {
                rewriteService = makeRewriteService(rewriteConfiguration, networkSession)
                rewriteProvider = rewriteConfiguration.provider
            } else {
                rewriteService = nil
                rewriteProvider = nil
            }
        }

        return DictationPipeline(
            transcriptionService: transcriptionService,
            transcriptionLanguageCode: transcriptionLanguageCode,
            promptProvider: promptProvider,
            rewriteService: rewriteService,
            rewriteProvider: rewriteProvider,
            preferredSpellings: preferredSpellings,
            usesAudienceAwareLocalPrompts: usesAudienceAwareLocalPrompts
        )
    }

    /// The current local transcription baseline is SenseVoice on every
    /// supported macOS language path. Stored legacy engine preferences are
    /// intentionally ignored until multiple local engines are reintroduced.
    nonisolated static func makeLiveLocalTranscriptionService(
        configuration: any ModelStorageConfiguration = UserDefaultsModelStorage()
    ) throws -> any AudioFileTranscriptionService {
        #if os(macOS)
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet", category: "PipelineFactory").info(
                "DictationPipelineFactory selected local engine=SenseVoice"
            )
            _ = configuration
            return try SherpaOnnxSenseVoiceTranscriptionService()
        #else
            return try LocalWhisperTranscriptionService(
                modelManager: LocalWhisperModelManager(configuration: configuration))
        #endif
    }

    nonisolated static func makeTranscriptionPrompt(
        preferredSpellings: [String]
    ) -> String? {
        guard !preferredSpellings.isEmpty else { return nil }
        return preferredSpellings.joined(separator: ", ")
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
