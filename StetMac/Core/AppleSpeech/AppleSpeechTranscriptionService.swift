#if os(macOS)
    import AVFoundation
    import Foundation
    import Speech

    enum AppleSpeechAssetState: Sendable, Equatable {
        case requiresMacOS26
        case unavailable
        case unsupportedLocale
        case available
        case downloading
        case installed
        case failed(String)

        var statusText: String {
            switch self {
            case .requiresMacOS26:
                return "Requires macOS 26 or newer"
            case .unavailable:
                return "Unavailable on this Mac"
            case .unsupportedLocale:
                return "Selected language is unsupported"
            case .available:
                return "Available"
            case .downloading:
                return "Downloading"
            case .installed:
                return "Installed"
            case .failed:
                return "Download failed"
            }
        }

        var isInstalled: Bool { self == .installed }
        var isDownloading: Bool { self == .downloading }
        var canDownload: Bool {
            switch self {
            case .available, .failed:
                return true
            default:
                return false
            }
        }

        var errorMessage: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    enum AppleSpeechError: LocalizedError, Equatable {
        case unavailable
        case assetInstallationFailed
        case fileNotFound(URL)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Apple Speech is unavailable on this Mac."
            case .assetInstallationFailed:
                return "The Apple Speech language model could not be installed."
            case .fileNotFound:
                return "The recorded audio file could not be found."
            }
        }
    }

    enum AppleSpeechSupport {
        static var isAvailable: Bool {
            guard #available(macOS 26.0, *) else { return false }
            return SpeechTranscriber.isAvailable
        }

        static func assetState(for languageCode: String) async -> AppleSpeechAssetState {
            guard #available(macOS 26.0, *) else { return .requiresMacOS26 }
            guard SpeechTranscriber.isAvailable else { return .unavailable }

            do {
                let locale = try await AppleSpeechLocaleResolver.resolve(languageCode)
                let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
                return switch await AssetInventory.status(forModules: [transcriber]) {
                case .unsupported: .unsupportedLocale
                case .supported: .available
                case .downloading: .downloading
                case .installed: .installed
                @unknown default: .unavailable
                }
            } catch is CancellationError {
                return .unavailable
            } catch SpeechServiceError.unsupportedLocale {
                return .unsupportedLocale
            } catch {
                return .failed(error.localizedDescription)
            }
        }

        static func installAsset(for languageCode: String) async throws {
            guard #available(macOS 26.0, *), SpeechTranscriber.isAvailable else {
                throw AppleSpeechError.unavailable
            }

            let locale = try await AppleSpeechLocaleResolver.resolve(languageCode)
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            try await AppleSpeechAssetManager.shared.ensureInstalled(for: transcriber, locale: locale)
        }
    }

    @available(macOS 26.0, *)
    enum AppleSpeechLocaleResolver {
        static func resolve(_ languageCode: String?) async throws -> Locale {
            let requested = Locale(identifier: preferredLocaleIdentifier(for: languageCode))
            guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
                throw SpeechServiceError.unsupportedLocale
            }
            return supported
        }

        static func preferredLocaleIdentifier(for languageCode: String?) -> String {
            switch languageCode ?? "en" {
            case "en": return matchingCurrentRegion(for: "en") ?? "en-US"
            case "zh", "zh-Hans": return "zh-CN"
            case "zh-Hant": return "zh-TW"
            case "ja": return "ja-JP"
            case "ko": return "ko-KR"
            case "fr": return matchingCurrentRegion(for: "fr") ?? "fr-FR"
            case "de": return matchingCurrentRegion(for: "de") ?? "de-DE"
            case "es": return matchingCurrentRegion(for: "es") ?? "es-ES"
            case "pt": return matchingCurrentRegion(for: "pt") ?? "pt-BR"
            case "it": return matchingCurrentRegion(for: "it") ?? "it-IT"
            case let identifier: return identifier
            }
        }

        private static func matchingCurrentRegion(for languageCode: String) -> String? {
            let current = Locale.autoupdatingCurrent
            guard current.language.languageCode?.identifier == languageCode,
                let region = current.region?.identifier
            else { return nil }
            return "\(languageCode)-\(region)"
        }
    }

    @available(macOS 26.0, *)
    actor AppleSpeechAssetManager {
        static let shared = AppleSpeechAssetManager()

        func ensureInstalled(for transcriber: SpeechTranscriber, locale: Locale) async throws {
            switch await AssetInventory.status(forModules: [transcriber]) {
            case .installed:
                return
            case .unsupported:
                throw SpeechServiceError.unsupportedLocale
            case .supported, .downloading:
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
                guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
                    throw AppleSpeechError.assetInstallationFailed
                }
            @unknown default:
                throw AppleSpeechError.unavailable
            }
        }

    }

    @available(macOS 26.0, *)
    struct AppleSpeechTranscriptionService: AudioFileTranscriptionService {
        typealias LocaleResolver = @Sendable (String?) async throws -> Locale
        typealias FileTranscriber = @Sendable (URL, Locale) async throws -> String

        private let resolveLocale: LocaleResolver
        private let transcribeFile: FileTranscriber

        init(
            resolveLocale: @escaping LocaleResolver = AppleSpeechLocaleResolver.resolve,
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
                throw AppleSpeechError.fileNotFound(fileURL)
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
            guard SpeechTranscriber.isAvailable else { throw AppleSpeechError.unavailable }

            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            try await AppleSpeechAssetManager.shared.ensureInstalled(for: transcriber, locale: locale)

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
