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
    transcriptionProviderConfiguration: TranscriptionProviderConfiguration? = nil,
    rewriteProviderConfiguration: RewriteProviderConfiguration? =
        DictationProviderConfigurationResolver.rewriteConfiguration(
            apiKey: "sk-test",
            providerPair: DictationProviderPair(transcriptionProvider: .openAI, rewriteProvider: .openAI)
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
        transcriptionProviderConfiguration: transcriptionProviderConfiguration,
        rewriteProviderConfiguration: rewriteProviderConfiguration,
        personalDictionary: personalDictionary,
        interactionSoundsEnabled: true,
        interactionSoundPreset: .soft
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
            transcriptionProviderConfiguration: nil,
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

    @Test func dictationExecutionRouteResolverAllowsByokWhenOnlyTranscriptionKeyIsMissing() async throws {
        let snapshot = makeSnapshot(
            transcriptionProvider: .groq,
            rewriteProvider: .openAI,
            transcriptionProviderConfiguration: nil,
            rewriteProviderConfiguration: DictationProviderConfigurationResolver.rewriteConfiguration(
                apiKey: "sk-test",
                providerPair: DictationProviderPair(
                    transcriptionProvider: .groq,
                    rewriteProvider: .openAI
                )
            )
        )

        let route = try await DictationExecutionRouteResolver.resolve(
            snapshot: snapshot
        )

        switch route {
        case .direct(let direct):
            #expect(direct.rewriteEnabled == false)
            #expect(direct.rewriteConfiguration == nil)
        }
    }

    @Test func dictationExecutionRouteResolverAllowsByokWhenOnlyRewriteKeyIsMissingByFallingBack() async throws {
        let snapshot = makeSnapshot(
            transcriptionProvider: .groq,
            rewriteProvider: .openAI,
            transcriptionProviderConfiguration: DictationProviderConfigurationResolver.transcriptionConfiguration(
                apiKey: "gsk-test",
                providerPair: DictationProviderPair(
                    transcriptionProvider: .groq,
                    rewriteProvider: .openAI
                )
            ),
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
            transcriptionProviderConfiguration: DictationProviderConfigurationResolver.transcriptionConfiguration(
                apiKey: "sk-test",
                providerPair: DictationProviderPair(
                    transcriptionProvider: .openAI,
                    rewriteProvider: .groq
                )
            ),
            rewriteProviderConfiguration: DictationProviderConfigurationResolver.rewriteConfiguration(
                apiKey: "gsk-test",
                providerPair: DictationProviderPair(
                    transcriptionProvider: .openAI,
                    rewriteProvider: .groq
                )
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
        let providerPair = DictationProviderPair(
            transcriptionProvider: .openAI,
            rewriteProvider: .appleIntelligence
        )
        let snapshot = makeSnapshot(
            rewriteProvider: .appleIntelligence,
            rewriteProviderConfiguration: DictationProviderConfigurationResolver.rewriteConfiguration(
                apiKey: "",
                providerPair: providerPair
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
            transcriptionProviderConfiguration: DictationProviderConfigurationResolver.transcriptionConfiguration(
                apiKey: "gsk-test",
                providerPair: DictationProviderPair(
                    transcriptionProvider: .groq,
                    rewriteProvider: .openAI
                )
            ),
            rewriteProviderConfiguration: DictationProviderConfigurationResolver.rewriteConfiguration(
                apiKey: "sk-test",
                providerPair: DictationProviderPair(
                    transcriptionProvider: .groq,
                    rewriteProvider: .openAI
                )
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

    @Test func textRewriteRequestCleanupDefaultsNilAudienceToHumanPrompt() {
        let request = TextRewriteRequest.cleanup(
            "raw transcript",
            preferredSpellings: ["Groq"]
        )

        #expect(request.text == "raw transcript")
        #expect(request.audience == nil)
        #expect(request.preferredSpellings == ["Groq"])
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
