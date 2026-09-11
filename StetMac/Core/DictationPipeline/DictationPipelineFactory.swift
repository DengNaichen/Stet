import Foundation
import StetAI
import StetCore
import StetRewrite

struct DictationPipeline: Sendable {
    let transcriptionService: any AudioFileTranscriptionService
    let transcriptionLanguageCode: String?
    let promptProvider: (@Sendable () async -> String?)?
    let rewriteService: (any TextRewriteService)?
    let rewriteProvider: DictationProvider?
    let preferredSpellings: [String]
    let usesAudienceAwareLocalPrompts: Bool
    let recordsNoHotwordTranscript: Bool
}

struct DictationPipelineFactory: Sendable {
    var makeLocalTranscriptionService: @Sendable () throws -> any AudioFileTranscriptionService
    var makeRewriteService: @Sendable (RewriteProviderConfiguration, URLSession) -> any TextRewriteService
    var recordsNoHotwordTranscript: Bool?

    init(
        makeLocalTranscriptionService: @escaping @Sendable () throws -> any AudioFileTranscriptionService,
        makeRewriteService:
            @escaping @Sendable (
                RewriteProviderConfiguration,
                URLSession
            ) -> any TextRewriteService,
        recordsNoHotwordTranscript: Bool? = nil
    ) {
        self.makeLocalTranscriptionService = makeLocalTranscriptionService
        self.makeRewriteService = makeRewriteService
        self.recordsNoHotwordTranscript = recordsNoHotwordTranscript
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
            let records =
                snapshot.personalDictionaryRecords.isEmpty
                ? FunASRNanoHotwordPrompt.records(from: preferredSpellings)
                : snapshot.personalDictionaryRecords
            promptProvider = Self.makePromptProvider(
                records: records,
                engine: snapshot.transcriptionEngine
            )
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
            usesAudienceAwareLocalPrompts: usesAudienceAwareLocalPrompts,
            recordsNoHotwordTranscript: recordsNoHotwordTranscript
                ?? Self.usesFunASRNano(transcriptionService)
        )
    }

    /// Instantiates the local engine selected in settings.
    nonisolated static func makeLiveLocalTranscriptionService(
        configuration: any ModelStorageConfiguration = UserDefaultsModelStorage()
    ) throws -> any AudioFileTranscriptionService {
        try LocalTranscriptionServiceFactory.make(configuration: configuration)
    }

    nonisolated static func makeTranscriptionPrompt(
        preferredSpellings: [String]
    ) -> String? {
        makeTranscriptionPrompt(
            records: FunASRNanoHotwordPrompt.records(from: preferredSpellings),
            engine: .fluidAudio
        )
    }

    nonisolated static func makeTranscriptionPrompt(
        records: [GlossaryEntry],
        engine: StoredTranscriptionEngine
    ) -> String? {
        switch engine {
        case .funASRNano:
            return FunASRNanoHotwordPrompt.makePrompt(from: records)
        case .fluidAudio, .localWhisper:
            guard !records.isEmpty else { return nil }
            return records.map(\.term).joined(separator: ", ")
        }
    }

    private nonisolated static func makePromptProvider(
        records: [GlossaryEntry],
        engine: StoredTranscriptionEngine
    ) -> (@Sendable () async -> String?)? {
        guard let prompt = makeTranscriptionPrompt(records: records, engine: engine) else {
            return nil
        }

        return { prompt }
    }

    nonisolated static func usesFunASRNano(_ service: any AudioFileTranscriptionService) -> Bool {
        #if os(macOS)
            return service is FunASRNanoTranscriptionService
        #else
            return false
        #endif
    }
}
