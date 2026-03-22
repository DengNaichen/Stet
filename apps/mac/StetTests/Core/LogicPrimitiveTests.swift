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
    provider: DictationProvider = .openAI,
    providerConfiguration: OpenAIConfiguration? = OpenAIConfiguration(apiKey: "sk-test", provider: .openAI),
    rewriteEnabled: Bool = false,
    dictationLanguageMode: DictationLanguageMode = .automatic,
    personalDictionary: [String] = []
) -> DictationSettingsSnapshot {
    DictationSettingsSnapshot(
        provider: provider,
        executionMode: mode,
        isRewriteEnabled: rewriteEnabled,
        dictationLanguageMode: dictationLanguageMode,
        shouldPauseMediaDuringDictation: false,
        providerConfiguration: providerConfiguration,
        personalDictionary: personalDictionary,
        interactionSoundsEnabled: true,
        interactionSoundPreset: .soft
    )
}

@Suite("Dictation Pipeline Logic")
struct LogicPrimitiveTests {
    @Test func dictationExecutionRouteResolverFallsBackToDirectForAutomaticWithoutRelay() async throws {
        let snapshot = makeSnapshot(mode: .automatic, providerConfiguration: OpenAIConfiguration(apiKey: "sk-test", provider: .openAI))

        let route = try await DictationExecutionRouteResolver.resolve(
            snapshot: snapshot,
            relayAuthentication: nil
        )

        switch route {
        case .direct(let direct):
            #expect(await direct.configuration.apiKey == "sk-test")
            #expect(await direct.rewriteEnabled == false)
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
            providerConfiguration: OpenAIConfiguration(apiKey: "sk-test", provider: .openAI),
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
        let snapshot = makeSnapshot(mode: .managed, providerConfiguration: OpenAIConfiguration(apiKey: "sk-test", provider: .openAI))

        await #expect(throws: AIExecutionError.managedRequiresAuthenticatedSession) {
            try await DictationExecutionRouteResolver.resolve(snapshot: snapshot, relayAuthentication: nil)
        }
    }

    @Test func dictationExecutionRouteResolverUsesByokWithLocalAPIKey() async throws {
        let snapshot = makeSnapshot(mode: .byok, providerConfiguration: OpenAIConfiguration(apiKey: "sk-test", provider: .openAI))

        let route = try await DictationExecutionRouteResolver.resolve(
            snapshot: snapshot,
            relayAuthentication: nil
        )

        switch route {
        case .direct(let direct):
            #expect(await direct.configuration.apiKey == "sk-test")
        default:
            Issue.record("Expected direct route for BYOK.")
        }
    }

    @Test func dictationExecutionRouteResolverRejectsByokWithoutLocalAPIKey() async {
        let snapshot = makeSnapshot(
            mode: .byok,
            providerConfiguration: nil
        )

        await #expect(throws: OpenAIError.missingAPIKey(provider: .openAI)) {
            try await DictationExecutionRouteResolver.resolve(snapshot: snapshot, relayAuthentication: nil)
        }
    }

    @Test func makePipelineSelectsDirectServiceForAutomaticWithoutRelay() async throws {
        let direct = RecordingTranscriptionService(result: "direct")
        let relay = RecordingTranscriptionService(result: "relay")
        let audioFileURL = try makeTemporaryWavURL()
        defer { try? FileManager.default.removeItem(at: audioFileURL) }
        let factory = DictationPipelineFactory(
            relayAuthenticationContext: { nil },
            makeDirectTranscriptionService: { _, _ in direct },
            makeRelayTranscriptionService: { _, _, _, _ in relay },
            makeRewriteService: { _, _ in RecordingRewriteService() }
        )
        let snapshot = makeSnapshot(
            mode: .automatic,
            providerConfiguration: OpenAIConfiguration(apiKey: "sk-test", provider: .openAI),
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
        #expect(pipeline.usesAudienceAwareLocalPrompts == false)
        #expect(await direct.callCount == 1)
        #expect(await relay.callCount == 0)
        #expect(await direct.capturedPrompt == nil)
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
            makeRelayTranscriptionService: { _, _, _, _ in relay },
            makeRewriteService: { _, _ in RecordingRewriteService() }
        )
        let snapshot = makeSnapshot(
            mode: .automatic,
            providerConfiguration: OpenAIConfiguration(apiKey: "sk-test", provider: .openAI),
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
        let factory = DictationPipelineFactory(
            relayAuthenticationContext: { nil },
            makeDirectTranscriptionService: { _, _ in direct },
            makeRelayTranscriptionService: { _, _, _, _ in relay },
            makeRewriteService: { _, _ in rewrite }
        )
        let snapshot = makeSnapshot(
            mode: .byok,
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
        #expect(prompt.contains("normalization") == true)
        #expect(prompt.contains("Aggressively fix obvious speech-to-text errors") == true)
        #expect(prompt.contains("Normalize fragmented spoken phrasing") == true)
        #expect(prompt.contains("direct and natural command or request style") == true)
        #expect(prompt.contains("bullet points, or steps") == true)
        #expect(prompt.contains("Do not add a title.") == true)
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
        #expect(aiRequest.systemPrompt?.contains("Do not add a title.") == true)
        #expect(aiRequest.systemPrompt?.contains("Cursor") == true)
    }

    @Test func makeTranscriptionPromptIncludesPreferredSpellings() {
        let prompt = DictationPipelineFactory.makeTranscriptionPrompt(preferredSpellings: ["OpenAI", "Groq"])

        let rendered = try! #require(prompt)
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
