import Foundation
import Testing

@testable import Stet

private func makeTemporaryWavURL() throws -> URL {
    let url = TestSupport.temporaryFileURL("logic-pipeline", ext: "wav")
    try Data("audio-bytes".utf8).write(to: url)
    return url
}

private func makeSnapshot(
    mode: AIExecutionMode,
    transcriptionProvider: DictationProvider = .openAI,
    rewriteProvider: DictationProvider = .openAI,
    transcriptionProviderConfiguration: OpenAIConfiguration? = OpenAIConfiguration.transcriptionConfiguration(
        apiKey: "sk-test",
        providerPair: DictationProviderPair(transcriptionProvider: .openAI, rewriteProvider: .openAI)
    ),
    rewriteProviderConfiguration: OpenAIConfiguration? = OpenAIConfiguration.rewriteConfiguration(
        apiKey: "sk-test",
        providerPair: DictationProviderPair(transcriptionProvider: .openAI, rewriteProvider: .openAI)
    ),
    dictationLanguageMode: DictationLanguageMode = .automatic,
    personalDictionary: [String] = []
) -> DictationSettingsSnapshot {
    DictationSettingsSnapshot(
        transcriptionProvider: transcriptionProvider,
        rewriteProvider: rewriteProvider,
        executionMode: mode,
        isRewriteEnabled: true,
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
    @Test func dictationExecutionRouteResolverFallsBackToDirectForAutomaticWithoutRelay() async throws {
        let snapshot = makeSnapshot(mode: .automatic)

        let route = try await DictationExecutionRouteResolver.resolve(
            snapshot: snapshot,
            relayAuthentication: nil
        )

        switch route {
        case .direct(let direct):
            #expect(await direct.transcriptionConfiguration.apiKey == "sk-test")
            #expect(await direct.rewriteConfiguration.apiKey == "sk-test")
            #expect(await direct.languageMode == .automatic)
            #expect(await direct.preferredSpellings.isEmpty)
        default:
            Issue.record("Expected direct route.")
        }
    }

    @Test func dictationExecutionRouteResolverPrefersRelayWhenAuthenticated() async throws {
        let relayAuthentication = RelayAuthenticationContext(
            functionsBaseURL: URL(string: "https://example.supabase.co/functions/v1")!,
            publishableKey: "anon-key",
            accessToken: "access-token"
        )
        let snapshot = makeSnapshot(
            mode: .automatic,
            personalDictionary: ["OpenAI"]
        )

        let route = try await DictationExecutionRouteResolver.resolve(
            snapshot: snapshot,
            relayAuthentication: relayAuthentication
        )

        switch route {
        case .relay(let relay):
            #expect(await relay.authentication == relayAuthentication)
            #expect(await relay.languageMode == .automatic)
            #expect(await relay.preferredSpellings.isEmpty == false)
        default:
            Issue.record("Expected relay route.")
        }
    }

    @Test func dictationExecutionRouteResolverRejectsManagedWithoutSession() async {
        let snapshot = makeSnapshot(mode: .managed)

        await #expect(throws: AIExecutionError.managedRequiresAuthenticatedSession) {
            try await DictationExecutionRouteResolver.resolve(snapshot: snapshot, relayAuthentication: nil)
        }
    }

    @Test func dictationExecutionRouteResolverUsesByokWithLocalAPIKey() async throws {
        let snapshot = makeSnapshot(mode: .byok)

        let route = try await DictationExecutionRouteResolver.resolve(
            snapshot: snapshot,
            relayAuthentication: nil
        )

        switch route {
        case .direct(let direct):
            #expect(await direct.transcriptionConfiguration.apiKey == "sk-test")
        default:
            Issue.record("Expected direct route for BYOK.")
        }
    }

    @Test func dictationExecutionRouteResolverRejectsByokWithoutRequiredProviderKeys() async {
        let snapshot = makeSnapshot(
            mode: .byok,
            transcriptionProviderConfiguration: nil,
            rewriteProviderConfiguration: nil
        )

        await #expect(
            throws: ProviderConfigurationError.missingRequirements([
                ProviderConfigurationRequirement(step: .transcription, provider: .openAI),
                ProviderConfigurationRequirement(step: .rewrite, provider: .openAI),
            ])
        ) {
            try await DictationExecutionRouteResolver.resolve(snapshot: snapshot, relayAuthentication: nil)
        }
    }

    @Test func dictationExecutionRouteResolverRejectsByokWhenOnlyTranscriptionKeyIsMissing() async {
        let snapshot = makeSnapshot(
            mode: .byok,
            transcriptionProvider: .groq,
            rewriteProvider: .openAI,
            transcriptionProviderConfiguration: nil,
            rewriteProviderConfiguration: OpenAIConfiguration.rewriteConfiguration(
                apiKey: "sk-test",
                providerPair: DictationProviderPair(
                    transcriptionProvider: .groq,
                    rewriteProvider: .openAI
                )
            )
        )

        await #expect(
            throws: ProviderConfigurationError.missingRequirements([
                ProviderConfigurationRequirement(step: .transcription, provider: .groq)
            ])
        ) {
            try await DictationExecutionRouteResolver.resolve(snapshot: snapshot, relayAuthentication: nil)
        }
    }

    @Test func dictationExecutionRouteResolverRejectsByokWhenOnlyRewriteKeyIsMissing() async {
        let snapshot = makeSnapshot(
            mode: .byok,
            transcriptionProvider: .groq,
            rewriteProvider: .openAI,
            transcriptionProviderConfiguration: OpenAIConfiguration.transcriptionConfiguration(
                apiKey: "gsk-test",
                providerPair: DictationProviderPair(
                    transcriptionProvider: .groq,
                    rewriteProvider: .openAI
                )
            ),
            rewriteProviderConfiguration: nil
        )

        await #expect(
            throws: ProviderConfigurationError.missingRequirements([
                ProviderConfigurationRequirement(step: .rewrite, provider: .openAI)
            ])
        ) {
            try await DictationExecutionRouteResolver.resolve(snapshot: snapshot, relayAuthentication: nil)
        }
    }

    @Test func dictationExecutionRouteResolverRejectsUnsupportedProviderPair() async {
        let snapshot = makeSnapshot(
            mode: .byok,
            transcriptionProvider: .openAI,
            rewriteProvider: .groq,
            transcriptionProviderConfiguration: OpenAIConfiguration.transcriptionConfiguration(
                apiKey: "sk-test",
                providerPair: DictationProviderPair(
                    transcriptionProvider: .openAI,
                    rewriteProvider: .groq
                )
            ),
            rewriteProviderConfiguration: nil
        )

        await #expect(
            throws: ProviderConfigurationError.unsupportedProviderCombination(
                DictationProviderPair(
                    transcriptionProvider: .openAI,
                    rewriteProvider: .groq
                )
            )
        ) {
            try await DictationExecutionRouteResolver.resolve(snapshot: snapshot, relayAuthentication: nil)
        }
    }

    @Test func makePipelineSelectsDirectServiceForAutomaticWithoutRelay() async throws {
        let direct = RecordingTranscriptionService(result: "direct")
        let relay = RecordingTranscriptionService(result: "relay")
        var capturedTranscriptionConfiguration: OpenAIConfiguration?
        var capturedRewriteConfiguration: OpenAIConfiguration?
        let audioFileURL = try makeTemporaryWavURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }
        let factory = DictationPipelineFactory(
            relayAuthenticationContext: { nil },
            makeDirectTranscriptionService: { configuration, _ in
                capturedTranscriptionConfiguration = configuration
                return direct
            },
            makeRelayTranscriptionService: { _, _, _ in relay },
            makeRewriteService: { configuration, _ in
                capturedRewriteConfiguration = configuration
                return RecordingRewriteService()
            }
        )
        let snapshot = makeSnapshot(
            mode: .automatic,
            personalDictionary: ["OpenAI", "Groq"]
        )

        let pipeline = try await factory.makePipeline(from: snapshot)
        let transcript = try await pipeline.transcriptionService.transcribe(
            audioFileAt: audioFileURL,
            languageCode: "en",
            prompt: pipeline.promptProvider == nil ? nil : "should-not-be-used",
            audioDurationSeconds: 1.2
        )

        #expect(transcript == "direct")
        #expect(pipeline.promptProvider == nil)
        #expect(pipeline.transcriptionLanguageCode == nil)
        #expect(pipeline.usesAudienceAwareLocalPrompts == false)
        #expect(await direct.callCount == 1)
        #expect(await relay.callCount == 0)
        #expect(await direct.capturedPrompt == nil)
        #expect(capturedTranscriptionConfiguration?.provider == .openAI)
        #expect(capturedRewriteConfiguration?.provider == .openAI)
    }

    @Test func makePipelineSelectsRelayServiceForAutomaticWithSession() async throws {
        let direct = RecordingTranscriptionService(result: "direct")
        let relay = RecordingTranscriptionService(result: "relay")
        let audioFileURL = try makeTemporaryWavURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let factory = DictationPipelineFactory(
            relayAuthenticationContext: {
                RelayAuthenticationContext(
                    functionsBaseURL: URL(string: "https://example.supabase.co/functions/v1")!,
                    publishableKey: "anon-key",
                    accessToken: "access-token"
                )
            },
            makeDirectTranscriptionService: { _, _ in direct },
            makeRelayTranscriptionService: { _, _, _ in relay },
            makeRewriteService: { _, _ in RecordingRewriteService() }
        )
        let snapshot = makeSnapshot(
            mode: .automatic,
            personalDictionary: ["OpenAI", "Groq"]
        )

        let pipeline = try await factory.makePipeline(from: snapshot)
        let transcript = try await pipeline.transcriptionService.transcribe(
            audioFileAt: audioFileURL,
            languageCode: "en",
            prompt: await pipeline.promptProvider?(),
            audioDurationSeconds: 1.2
        )

        #expect(transcript == "relay")
        #expect(await relay.callCount == 1)
        #expect(await direct.callCount == 0)
        #expect(pipeline.transcriptionLanguageCode == nil)
        #expect(await pipeline.promptProvider == nil)
        #expect(pipeline.usesAudienceAwareLocalPrompts == false)
    }

    @Test func makePipelineUsesConfiguredLanguageModeForTranscriptionAndCleanup() async throws {
        let direct = RecordingTranscriptionService(result: "mixed transcript")
        let relay = RecordingTranscriptionService(result: "relay")
        let rewrite = RecordingRewriteService()
        var capturedTranscriptionConfiguration: OpenAIConfiguration?
        var capturedRewriteConfiguration: OpenAIConfiguration?
        let factory = DictationPipelineFactory(
            relayAuthenticationContext: { nil },
            makeDirectTranscriptionService: { configuration, _ in
                capturedTranscriptionConfiguration = configuration
                return direct
            },
            makeRelayTranscriptionService: { _, _, _ in relay },
            makeRewriteService: { configuration, _ in
                capturedRewriteConfiguration = configuration
                return rewrite
            }
        )
        let snapshot = makeSnapshot(
            mode: .byok,
            transcriptionProvider: .groq,
            rewriteProvider: .openAI,
            transcriptionProviderConfiguration: OpenAIConfiguration.transcriptionConfiguration(
                apiKey: "gsk-test",
                providerPair: DictationProviderPair(
                    transcriptionProvider: .groq,
                    rewriteProvider: .openAI
                )
            ),
            rewriteProviderConfiguration: OpenAIConfiguration.rewriteConfiguration(
                apiKey: "sk-test",
                providerPair: DictationProviderPair(
                    transcriptionProvider: .groq,
                    rewriteProvider: .openAI
                )
            ),
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
                    transcript,
                    preferredSpellings: pipeline.preferredSpellings,
                    additionalUserContext: pipeline.rewriteAdditionalContext
                )
            )
        }

        #expect(transcript == "mixed transcript")
        #expect(pipeline.transcriptionLanguageCode == nil)
        #expect(pipeline.usesAudienceAwareLocalPrompts == true)
        #expect(pipeline.rewriteAdditionalContext?.contains("mix Chinese and English") == true)
        #expect(capturedTranscriptionConfiguration?.provider == .groq)
        #expect(capturedRewriteConfiguration?.provider == .openAI)
    }

    @Test func localRewritePromptBuilderBuildsHumanCleanupPrompt() {
        let prompt = LocalRewritePromptBuilder.systemPrompt(
            for: .dictationCleanup,
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
            for: .dictationCleanup,
            audience: .ai
        )

        #expect(prompt.contains("AI or coding tools") == true)
        #expect(prompt.contains("cleaning up a speech-to-text transcript") == true)
        #expect(prompt.contains("Fix obvious speech-to-text errors") == true)
        #expect(prompt.contains("Normalize fragmented spoken phrasing") == true)
        #expect(prompt.contains("Preserve the original language of the transcript") == true)
        #expect(prompt.contains("For very short transcripts or ambiguous fragments") == true)
        #expect(prompt.contains("direct and natural command or request style") == true)
        #expect(prompt.contains("simple numbering") == true)
        #expect(prompt.contains("Do not use bullets, headings, code fences, backticks") == true)
        #expect(prompt.contains("Do not add a title or wrap the result") == true)
        #expect(prompt.contains("agent") == false)
    }

    @Test func textRewriteRequestCleanupRetainsAudiencePromptAndAdditionalContext() {
        let request = TextRewriteRequest.cleanup(
            "raw transcript",
            audience: .human,
            preferredSpellings: ["Groq"],
            additionalUserContext: "Preserve mixed Chinese and English."
        )

        #expect(request.systemPrompt?.contains("IMPORTANT: You are a text cleanup tool.") == true)
        #expect(request.systemPrompt?.contains("Groq") == true)
        #expect(request.additionalUserContext == "Preserve mixed Chinese and English.")
    }

    @Test func textRewriteRequestSelectionRewriteBuildsAudienceSpecificPrompts() {
        let humanRequest = TextRewriteRequest.rewriteSelection(
            sourceText: "hello world",
            instruction: "Make it concise",
            audience: .human
        )
        let aiRequest = TextRewriteRequest.rewriteSelection(
            sourceText: "hello world",
            instruction: "Make it concise",
            audience: .ai,
            preferredSpellings: ["Cursor"]
        )

        #expect(humanRequest.systemPrompt?.contains("smallest edits needed") == true)
        #expect(humanRequest.systemPrompt?.contains("appropriate punctuation and capitalization") == true)
        #expect(aiRequest.systemPrompt?.contains("AI or coding context") == true)
        #expect(aiRequest.systemPrompt?.contains("clean, efficient written text") == true)
        #expect(aiRequest.systemPrompt?.contains("Normalize spoken or fragmented phrasing") == true)
        #expect(aiRequest.systemPrompt?.contains("simple numbering") == true)
        #expect(aiRequest.systemPrompt?.contains("Do not add a title.") == true)
        #expect(aiRequest.systemPrompt?.contains("Cursor") == true)
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
    ) async throws -> String {
        callCount += 1
        capturedPrompt = prompt
        capturedLanguageCode = languageCode
        switch outcome {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}
