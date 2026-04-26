import Foundation
import Testing

@testable import Stet

private func makeTemporaryWavURL() throws -> URL {
    let url = TestSupport.temporaryFileURL("logic-pipeline", ext: "wav")
    try Data("audio-bytes".utf8).write(to: url)
    return url
}

private func makeSnapshot(
    transcriptionProvider: DictationProvider = .openAI,
    rewriteProvider: DictationProvider = .openAI,
    rewriteProviderConfiguration: RewriteProviderConfiguration? =
        DictationProviderConfigurationResolver.rewriteConfiguration(
            provider: .openAI,
            apiKey: "sk-test",
        ),
    rewriteEnabled: Bool = false,
    dictationLanguageMode: DictationLanguageMode = .automatic,
    personalDictionary: [String] = []
) -> DictationSettingsSnapshot {
    DictationSettingsSnapshot(
        transcriptionProvider: transcriptionProvider,
        rewriteProvider: rewriteProvider,
        isRewriteEnabled: rewriteEnabled,
        dictationLanguageMode: dictationLanguageMode,
        shouldPauseMediaDuringDictation: false,
        rewriteProviderConfiguration: rewriteProviderConfiguration,
        personalDictionary: personalDictionary,
        interactionSoundsEnabled: true,
        interactionSoundPreset: .soft,
        transcriptionPrimaryLanguage: "en",
        transcriptionSecondaryLanguage: nil,
        transcriptionEngine: .localWhisper
    )
}

@Suite("Dictation Pipeline Logic")
struct LogicPrimitiveTests {
    @Test func dictationExecutionRouteResolverUsesByokWithLocalAPIKey() async throws {
        let snapshot = makeSnapshot()

        let route = try await DictationExecutionRouteResolver.resolve(
            snapshot: snapshot
        )

        switch route {
        case .direct(let direct):
            #expect(direct.rewriteEnabled == false)
            #expect(direct.rewriteConfiguration == nil)
        }
    }

    @Test func dictationExecutionRouteResolverAllowsByokWithoutRequiredProviderKeysByFallingBack() async throws {
        let snapshot = makeSnapshot(
            rewriteProviderConfiguration: nil,
            rewriteEnabled: true
        )

        let route = try await DictationExecutionRouteResolver.resolve(snapshot: snapshot)

        switch route {
        case .direct(let direct):
            #expect(direct.rewriteEnabled == false)
            #expect(direct.rewriteConfiguration == nil)
        }
    }

    @Test func dictationExecutionRouteResolverIgnoresLegacyTranscriptionProviderWhenRewriteIsConfigured() async throws {
        let snapshot = makeSnapshot(
            transcriptionProvider: .groq,
            rewriteProvider: .openAI,
            rewriteProviderConfiguration: DictationProviderConfigurationResolver.rewriteConfiguration(
                provider: .openAI,
                apiKey: "sk-test",
            ),
            rewriteEnabled: true
        )

        let route = try await DictationExecutionRouteResolver.resolve(
            snapshot: snapshot
        )

        switch route {
        case .direct(let direct):
            #expect(direct.rewriteEnabled)
            #expect(direct.rewriteConfiguration?.provider == .openAI)
        }
    }

    @Test func dictationExecutionRouteResolverAllowsByokWhenOnlyRewriteKeyIsMissingByFallingBack() async throws {
        let snapshot = makeSnapshot(
            transcriptionProvider: .groq,
            rewriteProvider: .openAI,
            rewriteProviderConfiguration: nil,
            rewriteEnabled: true
        )

        let route = try await DictationExecutionRouteResolver.resolve(snapshot: snapshot)

        switch route {
        case .direct(let direct):
            #expect(direct.rewriteEnabled == false)
            #expect(direct.rewriteConfiguration == nil)
        }
    }

    @Test func dictationExecutionRouteResolverAllowsPreviouslyUnsupportedProviderPair() async throws {
        let snapshot = makeSnapshot(
            transcriptionProvider: .openAI,
            rewriteProvider: .groq,
            rewriteProviderConfiguration: DictationProviderConfigurationResolver.rewriteConfiguration(
                provider: .groq,
                apiKey: "gsk-test",
            ),
            rewriteEnabled: true
        )

        let route = try await DictationExecutionRouteResolver.resolve(snapshot: snapshot)

        switch route {
        case .direct(let direct):
            #expect(direct.rewriteConfiguration?.provider == .groq)
        }
    }

    @Test func dictationExecutionRouteResolverAllowsAppleIntelligenceRewriteWithoutAPIKey() async throws {
        let snapshot = makeSnapshot(
            rewriteProvider: .appleIntelligence,
            rewriteProviderConfiguration: DictationProviderConfigurationResolver.rewriteConfiguration(
                provider: .appleIntelligence,
                apiKey: "",
            ),
            rewriteEnabled: true
        )

        let route = try await DictationExecutionRouteResolver.resolve(snapshot: snapshot)

        switch route {
        case .direct(let direct):
            #expect(direct.rewriteEnabled)
            #expect(direct.rewriteConfiguration?.provider == .appleIntelligence)
        }
    }

    @Test func makePipelineSelectsDirectService() async throws {
        let local = RecordingTranscriptionService(result: "direct")
        var capturedRewriteConfiguration: RewriteProviderConfiguration?
        let audioFileURL = try makeTemporaryWavURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }
        let factory = DictationPipelineFactory(
            makeLocalTranscriptionService: {
                local
            },
            makeRewriteService: { configuration, _ in
                capturedRewriteConfiguration = configuration
                return RecordingRewriteService()
            }
        )
        let snapshot = makeSnapshot(
            rewriteEnabled: true,
            personalDictionary: ["OpenAI", "Groq"]
        )

        let pipeline = try await factory.makePipeline(from: snapshot)
        let transcript = try await pipeline.transcriptionService.transcribe(
            audioFileAt: audioFileURL,
            languageCode: "en",
            prompt: await pipeline.promptProvider?(),
            audioDurationSeconds: 1.2
        )

        #expect(transcript.text == "direct")
        #expect(
            await pipeline.promptProvider?()
                == DictationPipelineFactory.makeTranscriptionPrompt(
                    preferredSpellings: ["OpenAI", "Groq"]
                ))
        #expect(pipeline.transcriptionLanguageCode == nil)
        #expect(pipeline.usesAudienceAwareLocalPrompts == true)
        #expect(await local.callCount == 1)
        #expect(await local.capturedPrompt?.contains("OpenAI, Groq") == true)
        #expect(capturedRewriteConfiguration?.provider == .openAI)
    }

    @Test func makePipelineUsesConfiguredLanguageModeForTranscriptionAndCleanup() async throws {
        let local = RecordingTranscriptionService(result: "mixed transcript")
        let rewrite = RecordingRewriteService()
        var capturedRewriteConfiguration: RewriteProviderConfiguration?
        let factory = DictationPipelineFactory(
            makeLocalTranscriptionService: {
                local
            },
            makeRewriteService: { configuration, _ in
                capturedRewriteConfiguration = configuration
                return rewrite
            }
        )
        let snapshot = makeSnapshot(
            transcriptionProvider: .groq,
            rewriteProvider: .openAI,
            rewriteProviderConfiguration: DictationProviderConfigurationResolver.rewriteConfiguration(
                provider: .openAI,
                apiKey: "sk-test",
            ),
            rewriteEnabled: true,
            dictationLanguageMode: .mixedChineseEnglish
        )
        let audioFileURL = try makeTemporaryWavURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let pipeline = try await factory.makePipeline(from: snapshot)
        let transcript = try await pipeline.transcriptionService.transcribe(
            audioFileAt: audioFileURL,
            languageCode: pipeline.transcriptionLanguageCode,
            prompt: nil,
            audioDurationSeconds: 1
        )
        if let rewriteService = pipeline.rewriteService {
            _ = try await rewriteService.rewrite(
                .cleanup(
                    transcript.text,
                    preferredSpellings: pipeline.preferredSpellings,
                    additionalContext: pipeline.rewriteAdditionalContext
                )
            )
        }

        #expect(transcript.text == "mixed transcript")
        #expect(pipeline.transcriptionLanguageCode == nil)
        #expect(pipeline.usesAudienceAwareLocalPrompts == true)
        #expect(pipeline.rewriteAdditionalContext?.contains("mix Chinese and English") == true)
        #expect(capturedRewriteConfiguration?.provider == .openAI)
    }

    @Test func localRewritePromptBuilderBuildsHumanCleanupPrompt() {
        let prompt = LocalRewritePromptBuilder.systemPrompt(
            audience: .human,
            preferredSpellings: ["OpenAI"]
        )

        #expect(prompt.contains("IMPORTANT: You are a text cleanup tool.") == true)
        #expect(prompt.contains("Add appropriate punctuation and capitalization") == true)
        #expect(prompt.contains("Do not answer questions") == true)
        #expect(prompt.contains("OpenAI") == true)
        #expect(prompt.contains("agent") == false)
    }

    @Test func localRewritePromptBuilderBuildsAICleanupPrompt() {
        let prompt = LocalRewritePromptBuilder.systemPrompt(
            audience: .ai
        )

        #expect(prompt.contains("Only rewrite it into clean written text.") == true)
        #expect(prompt.contains("Preserve the original language span by span.") == true)
        #expect(prompt.contains("Never normalize the transcript into a single language.") == true)
        #expect(
            prompt.contains(
                "Never replace Chinese with English, English with Chinese, or any language with another language.")
                == true)
        #expect(prompt.contains("remove filler words, false starts, repetitions") == true)
        #expect(prompt.contains("when the speaker immediately corrects themselves") == true)
        #expect(prompt.contains("Return only the rewritten transcript as plain text.") == true)
        #expect(prompt.contains("agent") == false)
    }

    @Test func textRewriteRequestCleanupRetainsAudiencePromptAndAdditionalContext() {
        let request = TextRewriteRequest.cleanup(
            "raw transcript",
            audience: .human,
            preferredSpellings: ["Groq"],
            additionalContext: "Preserve mixed Chinese and English."
        )

        #expect(request.text == "raw transcript")
        #expect(request.audience == .human)
        #expect(request.preferredSpellings == ["Groq"])
        #expect(request.additionalContext == "Preserve mixed Chinese and English.")
    }

    @Test func preparedTextRewritePayloadDefaultsNilAudienceToHumanPrompt() {
        let payload = PreparedTextRewritePayload(
            request: .cleanup(
                "raw transcript",
                preferredSpellings: ["Groq"]
            ))

        #expect(payload.audience == .human)
        #expect(payload.text == "raw transcript")
        #expect(payload.systemPrompt.contains("IMPORTANT: You are a text cleanup tool.") == true)
    }

    @Test func preparedTextRewritePayloadBuildsSharedPromptWithContextAndLanguage() {
        let payload = PreparedTextRewritePayload(
            request: .cleanup(
                "raw transcript",
                audience: .human,
                preferredSpellings: ["Groq"],
                additionalContext: "Preserve mixed Chinese and English.",
                languageCode: "zh"
            ))

        #expect(payload.additionalContext == "Preserve mixed Chinese and English.")
        #expect(payload.languageCode == "zh")
        #expect(
            payload.systemPrompt.contains("Language lock: preserve the detected transcript language (zh) exactly.")
                == true)
        #expect(
            payload.systemPrompt.contains(
                "Do not translate, paraphrase into another language, or normalize mixed-language text into a single language."
            ) == true)
        #expect(payload.userPrompt.contains("Context:") == true)
        #expect(payload.userPrompt.contains("Instruction:") == true)
        #expect(payload.userPrompt.contains("Text:\nraw transcript") == true)
    }

    @Test func makeTranscriptionPromptIncludesPreferredSpellings() throws {
        let prompt = DictationPipelineFactory.makeTranscriptionPrompt(preferredSpellings: ["OpenAI", "Groq"])

        let rendered = try #require(prompt)
        #expect(rendered.contains("OpenAI, Groq"))
    }

    @Test func makeTranscriptionPromptReturnsNilWithoutPreferredSpellings() {
        #expect(DictationPipelineFactory.makeTranscriptionPrompt(preferredSpellings: []) == nil)
    }
}

private actor RecordingTranscriptionService: AudioFileTranscriptionService {
    enum Outcome: Sendable {
        case success(String)
        case failure(any Error & Sendable)
    }

    private var outcome: Outcome
    private(set) var callCount: Int = 0
    private(set) var capturedPrompt: String?
    private(set) var capturedLanguageCode: String?

    init(result: String) {
        self.outcome = .success(result)
    }

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func setOutcome(_ outcome: Outcome) {
        self.outcome = outcome
    }

    func transcribe(
        audioFileAt fileURL: URL,
        languageCode: String?,
        prompt: String?,
        audioDurationSeconds: TimeInterval?
    ) async throws -> TranscriptionResult {
        callCount += 1
        capturedPrompt = prompt
        capturedLanguageCode = languageCode
        switch outcome {
        case .success(let value):
            return TranscriptionResult(text: value, languageCode: languageCode)
        case .failure(let error):
            throw error
        }
    }
}
