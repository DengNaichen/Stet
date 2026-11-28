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
    @Published var selectedLanguage: SpeechRecognitionLanguage {
        didSet {
            guard selectedLanguage != oldValue else { return }
            defaults.set(selectedLanguage.rawValue, forKey: Self.languageKey)
            statusCheckID = UUID()
            assetStatus = .checking
        }
    }

    @Published private(set) var assetStatus: SpeechAssetStatus = .checking

    private static let languageKey = "dictation.speechRecognitionLanguage"
    private let defaults: UserDefaults
    private var statusCheckID = UUID()
    private var installations: [SpeechRecognitionLanguage: Task<Locale, any Error>] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedLanguage =
            defaults.string(forKey: Self.languageKey).flatMap(SpeechRecognitionLanguage.init(rawValue:))
            ?? Self.preferredLanguage
    }

    func refreshAssetStatus() async {
        let language = selectedLanguage
        guard installations[language] == nil else { return }
        let checkID = UUID()
        statusCheckID = checkID

        let status: SpeechAssetStatus
        do {
            let locale = try await Self.resolve(language)
            let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
            status = Self.assetStatus(for: await AssetInventory.status(forModules: [transcriber]))
        } catch {
            status = .unsupported
        }

        guard statusCheckID == checkID, !Task.isCancelled else { return }
        assetStatus = status
    }

    func downloadAssetIfNeeded() async throws {
        _ = try await prepareLocale()
    }

    func resolvedLocale() async throws -> Locale {
        try await Self.resolve(selectedLanguage)
    }

    // Use the same locale for the asset check and the analyzer even if the selection changes.
    func prepareLocale() async throws -> Locale {
        try Task.checkCancellation()
        let language = selectedLanguage
        if let installation = installations[language] {
            let locale = try await installation.value
            try Task.checkCancellation()
            return locale
        }

        statusCheckID = UUID()
        let installation = Task {
            defer { installations[language] = nil }
            do {
                let locale = try await Self.resolve(language)
                let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
                switch await AssetInventory.status(forModules: [transcriber]) {
                case .installed:
                    break
                case .supported, .downloading:
                    publish(.downloading, for: language)
                    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                        try await request.downloadAndInstall()
                    }
                    guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
                        throw AssetError.installationIncomplete(language)
                    }
                case .unsupported:
                    throw AssetError.unsupported(language)
                @unknown default:
                    throw AssetError.installationIncomplete(language)
                }
                publish(.installed, for: language)
                return locale
            } catch let error as AssetError {
                switch error {
                case .unsupported: publish(.unsupported, for: language)
                case .installationIncomplete: publish(.failed(error.localizedDescription), for: language)
                }
                throw error
            } catch {
                publish(.failed(error.localizedDescription), for: language)
                throw error
            }
        }
        installations[language] = installation
        let locale = try await installation.value
        try Task.checkCancellation()
        return locale
    }

    private func publish(_ status: SpeechAssetStatus, for language: SpeechRecognitionLanguage) {
        guard selectedLanguage == language, assetStatus != status else { return }
        assetStatus = status
    }

    private static var preferredLanguage: SpeechRecognitionLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferred == "zh-hant" || preferred.hasPrefix("zh-hant-") { return .chineseTraditional }
        if preferred == "zh" || preferred.hasPrefix("zh-") { return .chineseSimplified }
        return .englishUS
    }

    private static func resolve(_ language: SpeechRecognitionLanguage) async throws -> Locale {
        let requested = Locale(identifier: language.localeIdentifier)
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requested) else {
            throw AssetError.unsupported(language)
        }
        return locale
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
