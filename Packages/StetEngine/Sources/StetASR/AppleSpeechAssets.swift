import Foundation
import Speech

public nonisolated enum AppleSpeechTranscriberBackend: String, CaseIterable, Identifiable, Sendable {
    case speechTranscriber
    case dictationTranscriber
    public var id: String { rawValue }
}

public nonisolated enum AppleSpeechMode: Hashable, Sendable {
    case file
    case streaming
}

public nonisolated enum AppleSpeechAssetStatus: Equatable, Sendable {
    case requiresOS26, unavailable, checking, unsupportedLocale, available, downloading, installed
    case failed(String)
    public var isInstalled: Bool { self == .installed }
    public var isDownloading: Bool { self == .downloading }
    public var canDownload: Bool {
        switch self {
        case .available, .failed: true
        default: false
        }
    }
    public var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }

    @available(macOS 26.0, iOS 26.0, *)
    public init(inventory: AssetInventory.Status) {
        switch inventory {
        case .installed: self = .installed
        case .supported: self = .available
        case .downloading: self = .downloading
        case .unsupported: self = .unsupportedLocale
        @unknown default: self = .unavailable
        }
    }
}

public nonisolated enum AppleSpeechAssetError: LocalizedError {
    case unsupportedLocale, unavailable, installationIncomplete
    public var errorDescription: String? {
        switch self {
        case .unsupportedLocale: "Apple Speech does not support the selected language."
        case .unavailable: "Apple Speech is unavailable on this device."
        case .installationIncomplete: "The Apple Speech language model could not be installed."
        }
    }
}

@available(macOS 26.0, iOS 26.0, *)
public nonisolated enum AppleSpeechLocaleResolver {
    public static func resolve(_ languageCode: String?, backend: AppleSpeechTranscriberBackend = .speechTranscriber)
        async throws -> Locale
    {
        let requested = Locale(identifier: preferredLocaleIdentifier(for: languageCode))
        let supported: Locale?
        switch backend {
        case .speechTranscriber:
            guard SpeechTranscriber.isAvailable else { throw AppleSpeechAssetError.unavailable }
            supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested)
        case .dictationTranscriber:
            supported = await DictationTranscriber.supportedLocale(equivalentTo: requested)
        }
        guard let supported else {
            throw AppleSpeechAssetError.unsupportedLocale
        }
        return supported
    }

    public static func preferredLocaleIdentifier(for languageCode: String?) -> String {
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

@available(macOS 26.0, iOS 26.0, *)
public nonisolated enum AppleSpeechModule {
    case speech(SpeechTranscriber)
    case dictation(DictationTranscriber)

    public init(locale: Locale, backend: AppleSpeechTranscriberBackend, mode: AppleSpeechMode) {
        switch backend {
        case .speechTranscriber: self = .speech(Self.speech(locale: locale, mode: mode))
        case .dictationTranscriber:
            self = .dictation(
                DictationTranscriber(locale: locale, preset: mode == .file ? .longDictation : .progressiveLongDictation)
            )
        }
    }

    public static func speech(locale: Locale, mode: AppleSpeechMode) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, preset: mode == .file ? .transcription : .progressiveTranscription)
    }

    public var modules: [any SpeechModule] {
        switch self {
        case .speech(let value): [value]
        case .dictation(let value): [value]
        }
    }
}

@available(macOS 26.0, iOS 26.0, *)
public actor AppleSpeechAssetManager {
    public static let shared = AppleSpeechAssetManager()
    private struct Key: Hashable {
        let locale: Locale
        let backend: AppleSpeechTranscriberBackend
        let mode: AppleSpeechMode
    }
    private var installations: [Key: Task<Void, Error>] = [:]

    public func status(for language: String, backend: AppleSpeechTranscriberBackend, mode: AppleSpeechMode) async
        -> AppleSpeechAssetStatus
    {
        do {
            let locale = try await AppleSpeechLocaleResolver.resolve(language, backend: backend)
            let key = Key(locale: locale, backend: backend, mode: mode)
            if installations[key] != nil { return .downloading }
            let modules = AppleSpeechModule(locale: locale, backend: backend, mode: mode).modules
            return AppleSpeechAssetStatus(inventory: await AssetInventory.status(forModules: modules))
        } catch AppleSpeechAssetError.unsupportedLocale {
            return .unsupportedLocale
        } catch AppleSpeechAssetError.unavailable {
            return .unavailable
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public func ensureInstalled(locale: Locale, backend: AppleSpeechTranscriberBackend, mode: AppleSpeechMode)
        async throws
    {
        let key = Key(locale: locale, backend: backend, mode: mode)
        if let installation = installations[key] {
            try await installation.value
        } else {
            let installation = Task {
                let modules = AppleSpeechModule(locale: locale, backend: backend, mode: mode).modules
                switch AppleSpeechAssetStatus(inventory: await AssetInventory.status(forModules: modules)) {
                case .installed: return
                case .unsupportedLocale: throw AppleSpeechAssetError.unsupportedLocale
                case .available, .downloading:
                    if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                        try await request.downloadAndInstall()
                    }
                    guard await AssetInventory.status(forModules: modules) == .installed else {
                        throw AppleSpeechAssetError.installationIncomplete
                    }
                default: throw AppleSpeechAssetError.unavailable
                }
            }
            installations[key] = installation
            defer { installations[key] = nil }
            try await installation.value
        }
        try Task.checkCancellation()
    }
}
