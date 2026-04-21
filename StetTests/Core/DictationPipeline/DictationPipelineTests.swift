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
        executionMode: mode,
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
    @Test func dictationExecutionRouteResolverRejectsManagedMode() async {
        let snapshot = makeSnapshot(mode: .managed)

        await #expect(throws: AIExecutionError.managedModeUnavailable) {
            try await DictationExecutionRouteResolver.resolve(
                snapshot: snapshot,
                relayAuthentication: RelayAuthenticationContext(
                    functionsBaseURL: URL(string: "https://example.supabase.co/functions/v1")!,
                    publishableKey: "anon-key",
                    accessToken: "access-token"
                )
            )
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
            #expect(direct.rewriteConfiguration?.provider == .openAI)
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
                ProviderConfigurationRequirement(step: .rewrite, provider: .openAI),
            ])
        ) {
            try await DictationExecutionRouteResolver.resolve(snapshot: snapshot, relayAuthentication: nil)
        }
    }

    @Test func dictationExecutionRouteResolverAllowsByokWhenOnlyTranscriptionKeyIsMissing() async throws {
        let snapshot = makeSnapshot(
            mode: .byok,
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
            snapshot: snapshot,
            relayAuthentication: nil
        )

        switch route {
        case .direct(let direct):
            #expect(direct.rewriteConfiguration?.provider == .openAI)
        default:
            Issue.record("Expected direct route.")
        }
    }

    @Test func dictationExecutionRouteResolverRejectsByokWhenOnlyRewriteKeyIsMissing() async {
        let snapshot = makeSnapshot(
            mode: .byok,
            transcriptionProvider: .groq,
            rewriteProvider: .openAI,
            transcriptionProviderConfiguration: DictationProviderConfigurationResolver.transcriptionConfiguration(
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

    @Test func dictationExecutionRouteResolverAllowsPreviouslyUnsupportedProviderPair() async throws {
        let snapshot = makeSnapshot(
            mode: .byok,
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

        let route = try await DictationExecutionRouteResolver.resolve(snapshot: snapshot, relayAuthentication: nil)

        switch route {
        case .direct(let direct):
            #expect(direct.rewriteConfiguration?.provider == .groq)
        default:
            Issue.record("Expected direct route.")
        }
    }

    @Test func makePipelineSelectsDirectServiceForByokWithoutRelay() async throws {
        let local = RecordingTranscriptionService(result: "direct")
        let relay = RecordingTranscriptionService(result: "relay")
        var capturedRewriteConfiguration: RewriteProviderConfiguration?
        let audioFileURL = try makeTemporaryWavURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }
        let factory = DictationPipelineFactory(
            relayAuthenticationContext: { nil },
            makeLocalTranscriptionService: {
                local
            },
            makeRelayTranscriptionService: { _, _, _ in relay },
            makeRewriteService: { configuration, _ in
                capturedRewriteConfiguration = configuration
                return RecordingRewriteService()
            }
        )
        let snapshot = makeSnapshot(
            mode: .byok,
            rewriteEnabled: true,
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
        #expect(pipeline.usesAudienceAwareLocalPrompts == true)
        #expect(await local.callCount == 1)
        #expect(await relay.callCount == 0)
        #expect(await local.capturedPrompt == nil)
        #expect(capturedRewriteConfiguration?.provider == .openAI)
    }

    @Test func makePipelineRejectsManagedMode() async {
        let factory = DictationPipelineFactory(
            relayAuthenticationContext: {
                RelayAuthenticationContext(
                    functionsBaseURL: URL(string: "https://example.supabase.co/functions/v1")!,
                    publishableKey: "anon-key",
                    accessToken: "access-token"
                )
            },
            makeLocalTranscriptionService: {
                RecordingTranscriptionService(result: "local")
            },
            makeRelayTranscriptionService: { _, _, _ in
                RecordingTranscriptionService(result: "relay")
            },
            makeRewriteService: { _, _ in
                RecordingRewriteService()
            }
        )
        let snapshot = makeSnapshot(mode: .managed)

        await #expect(throws: AIExecutionError.managedModeUnavailable) {
            try await factory.makePipeline(from: snapshot)
        }
    }

    @Test func makePipelineUsesConfiguredLanguageModeForTranscriptionAndCleanup() async throws {
        let local = RecordingTranscriptionService(result: "mixed transcript")
        let relay = RecordingTranscriptionService(result: "relay")
        let rewrite = RecordingRewriteService()
        var capturedRewriteConfiguration: RewriteProviderConfiguration?
        let factory = DictationPipelineFactory(
            relayAuthenticationContext: { nil },
            makeLocalTranscriptionService: {
                local
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

    @Test func textRewriteRequestCleanupDefaultsNilAudienceToHumanPrompt() {
        let request = TextRewriteRequest.cleanup(
            "raw transcript",
            preferredSpellings: ["Groq"]
        )

        #expect(request.systemPrompt?.contains("IMPORTANT: You are a text cleanup tool.") == true)
        #expect(request.systemPrompt?.contains("Groq") == true)
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
