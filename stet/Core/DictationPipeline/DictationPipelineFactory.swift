import Foundation

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

    static func live() -> Self {
        DictationPipelineFactory(
            makeLocalTranscriptionService: {
                try Self.makeLiveLocalTranscriptionService()
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

            let primary = snapshot.transcriptionPrimaryLanguage
            let secondary = snapshot.transcriptionSecondaryLanguage
            let engine = TranscriptionLanguageRouting.resolveEngine(primary: primary, secondary: secondary)
            switch engine {
            case .localWhisper(let hint):
                transcriptionLanguageCode = hint
            case .sherpaOnnxSenseVoice, .fluidAudio:
                transcriptionLanguageCode = primary
            }
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

    /// Picks which local-engine implementation to instantiate based on the
    /// user's `localTranscriptionEngine` preference. Whisper is the default and
    /// kept for the case where the Parakeet model isn't downloaded yet — we
    /// fall back to whisper rather than throwing so dictation never hard-fails
    /// because of a misconfigured picker.
    nonisolated static func makeLiveLocalTranscriptionService() throws -> any AudioFileTranscriptionService {
        #if os(macOS)
            let stored = StoredTranscriptionEngine.current()

            AppLogger.info(
                "DictationPipelineFactory selected local engine=\(stored.rawValue)",
                category: .dictation
            )

            switch stored {
            case .fluidAudio:
                do {
                    return try FluidAudioTranscriptionService()
                } catch {
                    AppLogger.warning(
                        "Parakeet engine unavailable (\(error.localizedDescription)); falling back to local whisper.",
                        category: .dictation
                    )
                    return try LocalWhisperTranscriptionService(modelManager: LocalWhisperModelManager())
                }
            case .localWhisper:
                return try LocalWhisperTranscriptionService(modelManager: LocalWhisperModelManager())
            case .sherpaOnnxSenseVoice:
                do {
                    return try SherpaOnnxSenseVoiceTranscriptionService(
                        modelManager: SherpaOnnxSenseVoiceModelManager())
                } catch {
                    AppLogger.warning(
                        "Sherpa-ONNX SenseVoice engine unavailable (\(error.localizedDescription)); falling back to local whisper.",
                        category: .dictation
                    )
                    return try LocalWhisperTranscriptionService(modelManager: LocalWhisperModelManager())
                }
            }
        #else
            return try LocalWhisperTranscriptionService(modelManager: LocalWhisperModelManager())
        #endif
    }

    private static let cleansingPrompt =
        "这是一段非常干净、流利、准确的多语言混合听抄记录。说话人可能会在中文、英文或其他语言之间自然切换，请务必保留每种语言的原始表达。输出内容不包含‘那个’、‘呃’、‘就是’等口语停顿词。 This is a clean, multi-language transcript where the speaker may naturally switch between languages. Filler words are removed."

    nonisolated static func makeTranscriptionPrompt(
        preferredSpellings: [String]
    ) -> String? {
        var sections: [String] = []

        // We lead with the cleansing prompt to set the tone for the transcription,
        // then append specific dictionary terms if available.
        sections.append(cleansingPrompt)

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
