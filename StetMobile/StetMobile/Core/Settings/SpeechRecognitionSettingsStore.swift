import Combine
import Foundation
import Speech

nonisolated enum SpeechRecognitionLanguage: String, CaseIterable, Identifiable, Sendable {
    case chineseSimplified = "zh-CN"
    case englishUS = "en-US"
    case chineseTraditional = "zh-TW"
    case japanese = "ja-JP"
    case korean = "ko-KR"

    var id: String { rawValue }
    var localeIdentifier: String { rawValue }

    var displayName: String {
        switch self {
        case .chineseSimplified: "中文（简体）"
        case .englishUS: "English (US)"
        case .chineseTraditional: "中文（繁體）"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }

    var shortLabel: String {
        switch self {
        case .chineseSimplified: "简体中文"
        case .englishUS: "English"
        case .chineseTraditional: "繁體中文"
        case .japanese, .korean: displayName
        }
    }
}

nonisolated enum SpeechTranscriberBackend: String, CaseIterable, Identifiable, Sendable {
    case speechTranscriber
    case dictationTranscriber

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .speechTranscriber: "SpeechTranscriber"
        case .dictationTranscriber: "DictationTranscriber"
        }
    }

    var subtitle: String {
        switch self {
        case .speechTranscriber: "Newer general speech model (better continuous Chinese; hotwords via Cloud Rewrite)"
        case .dictationTranscriber: "Keyboard dictation model (supports on-device contextual hotwords)"
        }
    }
}

nonisolated enum SpeechAssetStatus: Equatable, Sendable {
    case checking
    case installed
    case available
    case downloading
    case unsupported
    case failed(String)

    var isReady: Bool { self == .installed }
}

@MainActor
final class SpeechRecognitionSettingsStore: ObservableObject {
    struct PreparedSpeechTarget: Sendable {
        let locale: Locale
        let backend: SpeechTranscriberBackend
    }

    private struct AssetKey: Hashable {
        let language: SpeechRecognitionLanguage
        let backend: SpeechTranscriberBackend
    }

    @Published var selectedLanguage: SpeechRecognitionLanguage {
        didSet {
            guard selectedLanguage != oldValue else { return }
            defaults.set(selectedLanguage.rawValue, forKey: Self.languageKey)
            statusCheckID = UUID()
            assetStatus = .checking
        }
    }

    @Published var selectedBackend: SpeechTranscriberBackend {
        didSet {
            guard selectedBackend != oldValue else { return }
            defaults.set(selectedBackend.rawValue, forKey: Self.backendKey)
            statusCheckID = UUID()
            assetStatus = .checking
        }
    }

    @Published private(set) var assetStatus: SpeechAssetStatus = .checking

    private static let languageKey = "dictation.speechRecognitionLanguage"
    private static let backendKey = "dictation.speechTranscriberBackend"
    private let defaults: UserDefaults
    private var statusCheckID = UUID()
    private var installations: [AssetKey: Task<Locale, any Error>] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedLanguage =
            defaults.string(forKey: Self.languageKey).flatMap(SpeechRecognitionLanguage.init(rawValue:))
            ?? Self.preferredLanguage
        selectedBackend =
            defaults.string(forKey: Self.backendKey).flatMap(SpeechTranscriberBackend.init(rawValue:))
            ?? .speechTranscriber
    }

    func refreshAssetStatus() async {
        let key = AssetKey(language: selectedLanguage, backend: selectedBackend)
        guard installations[key] == nil else { return }
        let checkID = UUID()
        statusCheckID = checkID

        let status: SpeechAssetStatus
        do {
            let locale = try await Self.resolve(key.language, backend: key.backend)
            let modules = Self.makeModules(locale: locale, backend: key.backend)
            status = Self.assetStatus(for: await AssetInventory.status(forModules: modules))
        } catch {
            status = .unsupported
        }

        guard statusCheckID == checkID, !Task.isCancelled else { return }
        assetStatus = status
    }

    func downloadAssetIfNeeded() async throws {
        _ = try await prepareTarget()
    }

    func resolvedLocale() async throws -> Locale {
        try await Self.resolve(selectedLanguage, backend: selectedBackend)
    }

    func prepareLocale() async throws -> Locale {
        try await prepareTarget().locale
    }

    func prepareTarget() async throws -> PreparedSpeechTarget {
        try Task.checkCancellation()
        let key = AssetKey(language: selectedLanguage, backend: selectedBackend)
        if let installation = installations[key] {
            let locale = try await installation.value
            try Task.checkCancellation()
            return PreparedSpeechTarget(locale: locale, backend: key.backend)
        }

        statusCheckID = UUID()
        let installation = Task {
            defer { installations[key] = nil }
            do {
                let locale = try await Self.resolve(key.language, backend: key.backend)
                let modules = Self.makeModules(locale: locale, backend: key.backend)
                switch await AssetInventory.status(forModules: modules) {
                case .installed:
                    break
                case .supported, .downloading:
                    publish(.downloading, for: key)
                    if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                        try await request.downloadAndInstall()
                    }
                    guard await AssetInventory.status(forModules: modules) == .installed else {
                        throw AssetError.installationIncomplete(key.language)
                    }
                case .unsupported:
                    throw AssetError.unsupported(key.language)
                @unknown default:
                    throw AssetError.installationIncomplete(key.language)
                }
                publish(.installed, for: key)
                return locale
            } catch let error as AssetError {
                switch error {
                case .unsupported: publish(.unsupported, for: key)
                case .installationIncomplete: publish(.failed(error.localizedDescription), for: key)
                }
                throw error
            } catch {
                publish(.failed(error.localizedDescription), for: key)
                throw error
            }
        }
        installations[key] = installation
        let locale = try await installation.value
        try Task.checkCancellation()
        return PreparedSpeechTarget(locale: locale, backend: key.backend)
    }

    private func publish(_ status: SpeechAssetStatus, for key: AssetKey) {
        guard selectedLanguage == key.language, selectedBackend == key.backend, assetStatus != status else { return }
        assetStatus = status
    }

    private static var preferredLanguage: SpeechRecognitionLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferred == "zh-hant" || preferred.hasPrefix("zh-hant-") { return .chineseTraditional }
        if preferred == "zh" || preferred.hasPrefix("zh-") { return .chineseSimplified }
        return .englishUS
    }

    private static func resolve(
        _ language: SpeechRecognitionLanguage,
        backend: SpeechTranscriberBackend
    ) async throws -> Locale {
        let requested = Locale(identifier: language.localeIdentifier)
        let locale: Locale?
        switch backend {
        case .speechTranscriber:
            locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested)
        case .dictationTranscriber:
            locale = await DictationTranscriber.supportedLocale(equivalentTo: requested)
        }
        guard let locale else {
            throw AssetError.unsupported(language)
        }
        return locale
    }

    private static func makeModules(
        locale: Locale,
        backend: SpeechTranscriberBackend
    ) -> [any SpeechModule] {
        switch backend {
        case .speechTranscriber:
            [SpeechTranscriber(locale: locale, preset: .progressiveTranscription)]
        case .dictationTranscriber:
            [DictationTranscriber(locale: locale, preset: .progressiveLongDictation)]
        }
    }

    private static func assetStatus(for status: AssetInventory.Status) -> SpeechAssetStatus {
        switch status {
        case .installed: .installed
        case .supported: .available
        case .downloading: .downloading
        case .unsupported: .unsupported
        @unknown default: .failed("The Apple Speech language model status is unavailable.")
        }
    }

    private enum AssetError: LocalizedError {
        case unsupported(SpeechRecognitionLanguage)
        case installationIncomplete(SpeechRecognitionLanguage)

        var errorDescription: String? {
            switch self {
            case .unsupported(let language):
                "Apple Speech does not support \(language.displayName) on this device."
            case .installationIncomplete(let language):
                "The Apple Speech model for \(language.displayName) could not be installed."
            }
        }
    }
}
