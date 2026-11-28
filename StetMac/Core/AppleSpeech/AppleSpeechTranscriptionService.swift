#if os(macOS)
    import AVFoundation
    import Foundation
    import StetASR
    import Speech

    extension AppleSpeechAssetStatus {
        var statusText: String {
            switch self {
            case .checking: return String(localized: "Checking")
            case .requiresOS26:
                return String(localized: "Requires macOS 26 or newer")
            case .unavailable:
                return String(localized: "Unavailable on this Mac")
            case .unsupportedLocale:
                return String(localized: "Selected language is unsupported")
            case .available:
                return String(localized: "Available")
            case .downloading:
                return String(localized: "Downloading")
            case .installed:
                return String(localized: "Installed")
            case .failed:
                return String(localized: "Download failed")
            }
        }

    }

    enum AppleSpeechSupport {
        static var isAvailable: Bool {
            guard #available(macOS 26.0, *) else { return false }
            return SpeechTranscriber.isAvailable
        }

        static func assetState(for languageCode: String) async -> AppleSpeechAssetStatus {
            guard #available(macOS 26.0, *) else { return .requiresOS26 }
            return await AppleSpeechAssetManager.shared.status(
                for: languageCode, backend: .speechTranscriber, mode: .file)
        }

        static func installAsset(for languageCode: String) async throws {
            guard #available(macOS 26.0, *), SpeechTranscriber.isAvailable else {
                throw AppleSpeechAssetError.unavailable
            }

            let locale = try await AppleSpeechLocaleResolver.resolve(languageCode)
            try await AppleSpeechAssetManager.shared.ensureInstalled(
                locale: locale, backend: .speechTranscriber, mode: .file)
        }
    }

    @available(macOS 26.0, *)
    struct AppleSpeechTranscriptionService: AudioFileTranscriptionService {
        typealias LocaleResolver = @Sendable (String?) async throws -> Locale
        typealias FileTranscriber = @Sendable (URL, Locale) async throws -> String

        private let resolveLocale: LocaleResolver
        private let transcribeFile: FileTranscriber

        init(
            resolveLocale: @escaping LocaleResolver = { try await AppleSpeechLocaleResolver.resolve($0) },
            transcribeFile: @escaping FileTranscriber = Self.transcribeFile
        ) {
            self.resolveLocale = resolveLocale
            self.transcribeFile = transcribeFile
        }

        func transcribe(
            audioFileAt fileURL: URL,
            languageCode: String?,
            prompt _: String?,
            audioDurationSeconds _: TimeInterval?
        ) async throws -> TranscriptionResult {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: fileURL])
            }

            let locale = try await resolveLocale(languageCode)
            let rawText = try await transcribeFile(fileURL, locale)
            try Task.checkCancellation()
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw SpeechServiceError.emptyTranscription }

            return TranscriptionResult(
                text: text,
                languageCode: locale.language.languageCode?.identifier
            )
        }

        private static func transcribeFile(at fileURL: URL, locale: Locale) async throws -> String {
            guard SpeechTranscriber.isAvailable else { throw AppleSpeechAssetError.unavailable }

            let transcriber = AppleSpeechModule.speech(locale: locale, mode: .file)
            try await AppleSpeechAssetManager.shared.ensureInstalled(
                locale: locale, backend: .speechTranscriber, mode: .file)

            let audioFile = try AVAudioFile(forReading: fileURL)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let resultTask = Task { () throws -> String in
                var text = ""
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    guard result.isFinal else { continue }
                    text += String(result.text.characters)
                }
                return text
            }

            do {
                return try await withTaskCancellationHandler {
                    if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                        try await analyzer.finalizeAndFinish(through: lastSample)
                    } else {
                        await analyzer.cancelAndFinishNow()
                    }
                    return try await resultTask.value
                } onCancel: {
                    resultTask.cancel()
                    Task { await analyzer.cancelAndFinishNow() }
                }
            } catch {
                resultTask.cancel()
                await analyzer.cancelAndFinishNow()
                _ = try? await resultTask.value
                throw error
            }
        }
    }
#endif
