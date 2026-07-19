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

            transcriptionLanguageCode =
                snapshot.transcriptionEngine == .localWhisper
                ? nil
                : snapshot.transcriptionPrimaryLanguage
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

    /// Instantiates the local engine selected in settings. Alternative local
    /// engines retain the established Whisper fallback when they cannot be prepared.
    nonisolated static func makeLiveLocalTranscriptionService(
        configuration: any ModelStorageConfiguration = UserDefaultsModelStorage()
    ) throws -> any AudioFileTranscriptionService {
        #if os(macOS)
            let stored = configuration.transcriptionEngine

            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet", category: "PipelineFactory").info(
                "DictationPipelineFactory selected local engine=\(stored.rawValue)"
            )

            switch stored {
            case .fluidAudio:
                do {
                    return try FluidAudioTranscriptionService()
                } catch {
                    Logger(
                        subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
                        category: "PipelineFactory"
                    ).warning(
                        "Parakeet engine unavailable (\(error.localizedDescription)); falling back to local whisper."
                    )
                    return try LocalWhisperTranscriptionService(
                        modelManager: LocalWhisperModelManager(configuration: configuration)
                    )
                }
            case .funASRNano:
                do {
                    return try FunASRNanoTranscriptionService()
                } catch {
                    Logger(
                        subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
                        category: "PipelineFactory"
                    ).warning(
                        "Fun-ASR Nano unavailable (\(error.localizedDescription)); falling back to local whisper."
                    )
                    return try LocalWhisperTranscriptionService(
                        modelManager: LocalWhisperModelManager(configuration: configuration)
                    )
                }
            case .localWhisper:
                return try LocalWhisperTranscriptionService(
                    modelManager: LocalWhisperModelManager(configuration: configuration)
                )
            case .sherpaOnnxSenseVoice:
                do {
                    return try SherpaOnnxSenseVoiceTranscriptionService()
                } catch {
                    Logger(
                        subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
                        category: "PipelineFactory"
                    ).warning(
                        "SenseVoice engine unavailable (\(error.localizedDescription)); falling back to local whisper."
                    )
                    return try LocalWhisperTranscriptionService(
                        modelManager: LocalWhisperModelManager(configuration: configuration)
                    )
                }
            }
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
