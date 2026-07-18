import Foundation
import StetCore
import StetRewrite

struct MCPTranscriptionOutput: Codable, Equatable, Sendable {
    let text: String
    let rawText: String
    let languageCode: String
    let rewriteApplied: Bool
    let warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case text
        case rawText = "raw_text"
        case languageCode = "language_code"
        case rewriteApplied = "rewrite_applied"
        case warnings
    }
}

nonisolated protocol MCPTranscriptionServing: Sendable {
    func transcribe(audioPath: String) async throws -> MCPTranscriptionOutput
}

enum MCPTranscriptionError: LocalizedError, Sendable {
    case audioPathMustBeAbsolute
    case audioFileMissing(String)
    case audioFileIsNotRegular(String)
    case audioFileIsNotReadable(String)
    case emptyTranscription
    case emptyRewrite

    var errorDescription: String? {
        switch self {
        case .audioPathMustBeAbsolute:
            return "audio_path must be an absolute local file path."
        case .audioFileMissing(let path):
            return "Audio file does not exist: \(path)"
        case .audioFileIsNotRegular(let path):
            return "Audio path is not a regular file: \(path)"
        case .audioFileIsNotReadable(let path):
            return "Audio file is not readable: \(path)"
        case .emptyTranscription:
            return "SenseVoice returned an empty transcription."
        case .emptyRewrite:
            return "The configured rewrite provider returned empty text."
        }
    }
}

actor MCPTranscriptionCoordinator: MCPTranscriptionServing {
    typealias SettingsSnapshotProvider = @Sendable () -> DictationSettingsSnapshot

    private let settingsSnapshotProvider: SettingsSnapshotProvider
    private let pipelineFactory: DictationPipelineFactory
    private let fileManager: FileManager
    private var isProcessing = false
    private var processingWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        settingsSnapshotProvider: @escaping SettingsSnapshotProvider,
        pipelineFactory: DictationPipelineFactory,
        fileManager: FileManager = .default
    ) {
        self.settingsSnapshotProvider = settingsSnapshotProvider
        self.pipelineFactory = pipelineFactory
        self.fileManager = fileManager
    }

    init(
        settingsStore: DictationSettingsStore,
        pipelineFactory: DictationPipelineFactory
    ) {
        self.init(
            settingsSnapshotProvider: { settingsStore.loadSnapshot() },
            pipelineFactory: pipelineFactory
        )
    }

    func transcribe(audioPath: String) async throws -> MCPTranscriptionOutput {
        await acquireProcessingSlot()
        defer { releaseProcessingSlot() }

        let audioURL = try validatedAudioURL(for: audioPath)
        let snapshot = settingsSnapshotProvider()
        let pipeline = try await pipelineFactory.makePipeline(from: snapshot)

        let transcriptionPrompt: String?
        if let promptProvider = pipeline.promptProvider {
            transcriptionPrompt = await promptProvider()
        } else {
            transcriptionPrompt = nil
        }

        let transcription = try await pipeline.transcriptionService.transcribe(
            audioFileAt: audioURL,
            languageCode: pipeline.transcriptionLanguageCode,
            prompt: transcriptionPrompt,
            audioDurationSeconds: nil
        )
        let rawText = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            throw MCPTranscriptionError.emptyTranscription
        }

        let languageCode =
            transcription.languageCode ?? pipeline.transcriptionLanguageCode ?? "und"
        guard let rewriteService = pipeline.rewriteService else {
            return MCPTranscriptionOutput(
                text: rawText,
                rawText: rawText,
                languageCode: languageCode,
                rewriteApplied: false,
                warnings: []
            )
        }

        let request = TextRewriteRequest.cleanup(
            rawText,
            audience: .ai,
            preferredSpellings: pipeline.preferredSpellings,
            languageCode: languageCode
        )

        do {
            let rewrittenText = try await rewriteService.rewrite(request)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rewrittenText.isEmpty else {
                throw MCPTranscriptionError.emptyRewrite
            }
            return MCPTranscriptionOutput(
                text: rewrittenText,
                rawText: rawText,
                languageCode: languageCode,
                rewriteApplied: true,
                warnings: []
            )
        } catch {
            return MCPTranscriptionOutput(
                text: rawText,
                rawText: rawText,
                languageCode: languageCode,
                rewriteApplied: false,
                warnings: ["Rewrite failed; using raw transcription: \(error.localizedDescription)"]
            )
        }
    }

    private func acquireProcessingSlot() async {
        guard isProcessing else {
            isProcessing = true
            return
        }

        await withCheckedContinuation { continuation in
            processingWaiters.append(continuation)
        }
    }

    private func releaseProcessingSlot() {
        guard !processingWaiters.isEmpty else {
            isProcessing = false
            return
        }
        processingWaiters.removeFirst().resume()
    }

    private func validatedAudioURL(for audioPath: String) throws -> URL {
        guard NSString(string: audioPath).isAbsolutePath else {
            throw MCPTranscriptionError.audioPathMustBeAbsolute
        }

        let url = URL(fileURLWithPath: audioPath).standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw MCPTranscriptionError.audioFileMissing(url.path)
        }
        guard !isDirectory.boolValue else {
            throw MCPTranscriptionError.audioFileIsNotRegular(url.path)
        }

        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw MCPTranscriptionError.audioFileIsNotRegular(url.path)
        }
        guard fileManager.isReadableFile(atPath: url.path) else {
            throw MCPTranscriptionError.audioFileIsNotReadable(url.path)
        }
        return url
    }
}
