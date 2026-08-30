import Foundation
import StetAI
import StetCore
import StetRewrite
import Testing

@testable import Stet

@MainActor
@Suite("MCP Transcription Coordinator")
struct MCPTranscriptionCoordinatorTests {
    @Test func transcribesAndRewritesWithAIAudienceAndCurrentSettings() async throws {
        let audioURL = try makeReadableAudioPlaceholder()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let transcriptionService = MCPRecordingTranscriptionService(
            result: .init(text: " raw stet text ", languageCode: "zh")
        )
        let rewriteService = RecordingRewriteService()
        await rewriteService.setResult(" cleaned Stet text ")
        let coordinator = makeCoordinator(
            snapshot: makeMCPSnapshot(
                rewriteEnabled: true,
                personalDictionary: ["Stet"],
                primaryLanguage: "en"
            ),
            transcriptionService: transcriptionService,
            rewriteService: rewriteService
        )

        let output = try await coordinator.transcribe(audioPath: audioURL.path)

        #expect(output.text == "cleaned Stet text")
        #expect(output.rawText == "raw stet text")
        #expect(output.languageCode == "zh")
        #expect(output.rewriteApplied)
        #expect(output.warnings.isEmpty)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))

        let request = try #require(await rewriteService.recordedRequests().first)
        #expect(request.audience == .ai)
        #expect(request.preferredSpellings == ["Stet"])
        #expect(request.languageCode == "zh")
        #expect(request.appName == nil)
    }

    @Test func returnsRawTextWhenRewriteIsDisabled() async throws {
        let audioURL = try makeReadableAudioPlaceholder()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let rewriteService = RecordingRewriteService()
        let coordinator = makeCoordinator(
            snapshot: makeMCPSnapshot(rewriteEnabled: false),
            transcriptionService: MCPRecordingTranscriptionService(
                result: .init(text: "raw text", languageCode: nil)
            ),
            rewriteService: rewriteService
        )

        let output = try await coordinator.transcribe(audioPath: audioURL.path)

        #expect(output.text == "raw text")
        #expect(output.rawText == "raw text")
        #expect(output.languageCode == "en")
        #expect(!output.rewriteApplied)
        #expect(output.warnings.isEmpty)
        #expect(await rewriteService.recordedRequests().isEmpty)
    }

    @Test func fallsBackToRawTextWhenRewriteFails() async throws {
        let audioURL = try makeReadableAudioPlaceholder()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let rewriteService = RecordingRewriteService()
        await rewriteService.setError(TestError.expected)
        let coordinator = makeCoordinator(
            snapshot: makeMCPSnapshot(rewriteEnabled: true),
            transcriptionService: MCPRecordingTranscriptionService(
                result: .init(text: "raw fallback", languageCode: "en")
            ),
            rewriteService: rewriteService
        )

        let output = try await coordinator.transcribe(audioPath: audioURL.path)

        #expect(output.text == "raw fallback")
        #expect(!output.rewriteApplied)
        #expect(output.warnings.count == 1)
        #expect(output.warnings[0].contains("Rewrite failed"))
    }

    @Test func fallsBackToRawTextWhenRewriteReturnsEmptyText() async throws {
        let audioURL = try makeReadableAudioPlaceholder()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let rewriteService = RecordingRewriteService()
        await rewriteService.setResult("   ")
        let coordinator = makeCoordinator(
            snapshot: makeMCPSnapshot(rewriteEnabled: true),
            transcriptionService: MCPRecordingTranscriptionService(
                result: .init(text: "raw fallback", languageCode: "en")
            ),
            rewriteService: rewriteService
        )

        let output = try await coordinator.transcribe(audioPath: audioURL.path)

        #expect(output.text == "raw fallback")
        #expect(!output.rewriteApplied)
        #expect(output.warnings.first?.contains("empty text") == true)
    }

    @Test func rejectsRelativeAndMissingPathsBeforeTranscription() async {
        let transcriptionService = MCPRecordingTranscriptionService(
            result: .init(text: "unused", languageCode: nil)
        )
        let coordinator = makeCoordinator(
            snapshot: makeMCPSnapshot(rewriteEnabled: false),
            transcriptionService: transcriptionService,
            rewriteService: RecordingRewriteService()
        )

        await #expect(throws: MCPTranscriptionError.self) {
            try await coordinator.transcribe(audioPath: "relative/audio.wav")
        }
        await #expect(throws: MCPTranscriptionError.self) {
            try await coordinator.transcribe(
                audioPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .path
            )
        }
        #expect(await transcriptionService.callCount == 0)
    }

    @Test func rejectsEmptyTranscription() async throws {
        let audioURL = try makeReadableAudioPlaceholder()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let coordinator = makeCoordinator(
            snapshot: makeMCPSnapshot(rewriteEnabled: false),
            transcriptionService: MCPRecordingTranscriptionService(
                result: .init(text: "  ", languageCode: nil)
            ),
            rewriteService: RecordingRewriteService()
        )

        await #expect(throws: MCPTranscriptionError.self) {
            try await coordinator.transcribe(audioPath: audioURL.path)
        }
    }

    @Test func serializesConcurrentTranscriptionCalls() async throws {
        let firstURL = try makeReadableAudioPlaceholder()
        let secondURL = try makeReadableAudioPlaceholder()
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }

        let transcriptionService = MCPConcurrencyTrackingTranscriptionService()
        let coordinator = makeCoordinator(
            snapshot: makeMCPSnapshot(rewriteEnabled: false),
            transcriptionService: transcriptionService,
            rewriteService: RecordingRewriteService()
        )

        async let first = coordinator.transcribe(audioPath: firstURL.path)
        async let second = coordinator.transcribe(audioPath: secondURL.path)
        _ = try await (first, second)

        #expect(await transcriptionService.maximumConcurrentCalls == 1)
    }

    @Test func transcribesOptInWAVAndM4AFilesWithoutChangingSources() async throws {
        let pathsValue =
            ProcessInfo.processInfo.environment["STET_MCP_E2E_AUDIO_PATHS"]
            ?? "/private/tmp/stet-mcp-e2e.wav:/private/tmp/stet-mcp-e2e.m4a"
        let audioPaths = pathsValue.split(separator: ":").map(String.init)
        guard audioPaths.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) else {
            return
        }

        let snapshot = makeMCPSnapshot(rewriteEnabled: false)
        let coordinator = MCPTranscriptionCoordinator(
            settingsSnapshotProvider: { snapshot },
            pipelineFactory: .live()
        )

        for audioPath in audioPaths {
            let audioURL = URL(fileURLWithPath: audioPath)
            let originalData = try Data(contentsOf: audioURL)

            let output = try await coordinator.transcribe(audioPath: audioPath)

            #expect(!output.rawText.isEmpty)
            #expect(!output.rewriteApplied)
            #expect(FileManager.default.fileExists(atPath: audioPath))
            #expect(try Data(contentsOf: audioURL) == originalData)
        }
    }
}

private func makeCoordinator(
    snapshot: DictationSettingsSnapshot,
    transcriptionService: any AudioFileTranscriptionService,
    rewriteService: any TextRewriteService
) -> MCPTranscriptionCoordinator {
    let pipelineFactory = DictationPipelineFactory(
        makeLocalTranscriptionService: { transcriptionService },
        makeRewriteService: { _, _ in rewriteService }
    )
    return MCPTranscriptionCoordinator(
        settingsSnapshotProvider: { snapshot },
        pipelineFactory: pipelineFactory
    )
}

private func makeMCPSnapshot(
    rewriteEnabled: Bool,
    personalDictionary: [String] = [],
    primaryLanguage: String = "en"
) -> DictationSettingsSnapshot {
    DictationSettingsSnapshot(
        transcriptionProvider: .openAI,
        rewriteProvider: .openAI,
        isRewriteEnabled: rewriteEnabled,
        selectedModel: nil,
        shouldPauseMediaDuringDictation: false,
        rewriteProviderConfiguration: rewriteEnabled
            ? DictationProviderConfigurationResolver.rewriteConfiguration(
                provider: .openAI,
                apiKey: "sk-test"
            ) : nil,
        personalDictionary: personalDictionary,
        interactionSoundsEnabled: true,
        interactionSoundPreset: .soft,
        transcriptionPrimaryLanguage: primaryLanguage,
        transcriptionSecondaryLanguage: nil,
        transcriptionEngine: .funASRNano
    )
}

private func makeReadableAudioPlaceholder() throws -> URL {
    let url = TestSupport.temporaryFileURL("mcp-\(UUID().uuidString)", ext: "wav")
    try Data("audio-placeholder".utf8).write(to: url)
    return url
}

private nonisolated final class MCPRecordingTranscriptionService:
    AudioFileTranscriptionService, @unchecked Sendable
{
    let result: TranscriptionResult
    private let lock = NSLock()
    private var storedCallCount = 0

    var callCount: Int {
        lock.withLock { storedCallCount }
    }

    init(result: TranscriptionResult) {
        self.result = result
    }

    func transcribe(
        audioFileAt _: URL,
        languageCode _: String?,
        prompt _: String?,
        audioDurationSeconds _: TimeInterval?
    ) async throws -> TranscriptionResult {
        lock.withLock { storedCallCount += 1 }
        return result
    }
}

private nonisolated final class MCPConcurrencyTrackingTranscriptionService:
    AudioFileTranscriptionService, @unchecked Sendable
{
    private struct State {
        var activeCalls = 0
        var maximumConcurrentCalls = 0
    }

    private let lock = NSLock()
    private var state = State()

    var maximumConcurrentCalls: Int {
        lock.withLock { state.maximumConcurrentCalls }
    }

    func transcribe(
        audioFileAt _: URL,
        languageCode: String?,
        prompt _: String?,
        audioDurationSeconds _: TimeInterval?
    ) async throws -> TranscriptionResult {
        lock.withLock {
            state.activeCalls += 1
            state.maximumConcurrentCalls = max(
                state.maximumConcurrentCalls,
                state.activeCalls
            )
        }
        defer {
            lock.withLock { state.activeCalls -= 1 }
        }
        try await Task.sleep(for: .milliseconds(30))
        return TranscriptionResult(text: "transcribed", languageCode: languageCode)
    }
}
