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
    personalDictionary: [String] = []
) -> DictationSettingsSnapshot {
    DictationSettingsSnapshot(
        provider: provider,
        executionMode: mode,
        isRewriteEnabled: rewriteEnabled,
        shouldPauseMediaDuringDictation: false,
        providerConfiguration: providerConfiguration,
        translationTargetLanguage: .english,
        translateSelectedTextOnTranslationHotkey: false,
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
        #expect(await pipeline.promptProvider == nil)
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
