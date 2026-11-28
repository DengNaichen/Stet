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

extension AppleSpeechTranscriberBackend {
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

nonisolated enum MicrophoneKeepAliveDuration: String, CaseIterable, Identifiable, Sendable {
    case fiveMinutes = "5m"
    case thirtyMinutes = "30m"
    case twoHours = "2h"
    case never = "never"

    var id: String { rawValue }

    /// Idle duration before releasing the background microphone session.
    /// `nil` keeps standby active indefinitely.
    var timeoutDuration: Duration? {
        switch self {
        case .fiveMinutes: .seconds(5 * 60)
        case .thirtyMinutes: .seconds(30 * 60)
        case .twoHours: .seconds(2 * 60 * 60)
        case .never: nil
        }
    }

    var displayName: String {
        switch self {
        case .fiveMinutes: "5 Minutes"
        case .thirtyMinutes: "30 Minutes"
        case .twoHours: "2 Hours"
        case .never: "Never"
        }
    }

    var shortLabel: String {
        switch self {
        case .fiveMinutes: "5 min"
        case .thirtyMinutes: "30 min"
        case .twoHours: "2 hr"
        case .never: "Never"
        }
    }

    var footerDescription: String {
        switch self {
        case .never:
            "Keeps the microphone in standby indefinitely for instant keyboard dictation without switching apps."
        case .fiveMinutes, .thirtyMinutes, .twoHours:
            "Releases the background microphone and ends the Live Activity after \(displayName.lowercased()) of inactivity. The keyboard will briefly open Stet to wake the mic on your next dictation."
        }
    }
}

@MainActor
final class SpeechRecognitionSettingsStore: ObservableObject {
    struct PreparedSpeechTarget: Sendable {
        let locale: Locale
        let backend: AppleSpeechTranscriberBackend
    }

    private struct AssetKey: Hashable {
        let language: SpeechRecognitionLanguage
        let backend: AppleSpeechTranscriberBackend
    }

    @Published var selectedLanguage: SpeechRecognitionLanguage {
        didSet {
            guard selectedLanguage != oldValue else { return }
            defaults.set(selectedLanguage.rawValue, forKey: Self.languageKey)
            statusCheckID = UUID()
            assetStatus = .checking
        }
    }

    @Published var selectedBackend: AppleSpeechTranscriberBackend {
        didSet {
            guard selectedBackend != oldValue else { return }
            defaults.set(selectedBackend.rawValue, forKey: Self.backendKey)
            statusCheckID = UUID()
            assetStatus = .checking
        }
    }

    @Published var microphoneKeepAliveDuration: MicrophoneKeepAliveDuration {
        didSet {
            guard microphoneKeepAliveDuration != oldValue else { return }
            defaults.set(microphoneKeepAliveDuration.rawValue, forKey: Self.microphoneKeepAliveKey)
        }
    }

    @Published private(set) var assetStatus: AppleSpeechAssetStatus = .checking

    private static let languageKey = "dictation.speechRecognitionLanguage"
    private static let backendKey = "dictation.speechTranscriberBackend"
    private static let microphoneKeepAliveKey = "dictation.microphoneKeepAliveDuration"
    private let defaults: UserDefaults
    private var statusCheckID = UUID()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedLanguage =
            defaults.string(forKey: Self.languageKey).flatMap(SpeechRecognitionLanguage.init(rawValue:))
            ?? Self.preferredLanguage
        selectedBackend =
            defaults.string(forKey: Self.backendKey).flatMap(AppleSpeechTranscriberBackend.init(rawValue:))
            ?? .speechTranscriber
        microphoneKeepAliveDuration =
            defaults.string(forKey: Self.microphoneKeepAliveKey)
            .flatMap(MicrophoneKeepAliveDuration.init(rawValue:))
            ?? .twoHours
    }

    func refreshAssetStatus() async {
        let key = AssetKey(language: selectedLanguage, backend: selectedBackend)
        let checkID = UUID()
        statusCheckID = checkID

        let status = await AppleSpeechAssetManager.shared.status(
            for: key.language.localeIdentifier, backend: key.backend, mode: .streaming)
        guard statusCheckID == checkID, !Task.isCancelled else { return }
        assetStatus = status
    }

    func downloadAssetIfNeeded() async throws {
        _ = try await prepareTarget()
    }

    func prepareLocale() async throws -> Locale {
        try await prepareTarget().locale
    }

    func prepareTarget() async throws -> PreparedSpeechTarget {
        try Task.checkCancellation()
        let key = AssetKey(language: selectedLanguage, backend: selectedBackend)
        statusCheckID = UUID()
        if !assetStatus.isInstalled { assetStatus = .downloading }
        do {
            let locale = try await AppleSpeechLocaleResolver.resolve(
                key.language.localeIdentifier, backend: key.backend)
            try await AppleSpeechAssetManager.shared.ensureInstalled(
                locale: locale, backend: key.backend, mode: .streaming)
            if selectedLanguage == key.language, selectedBackend == key.backend {
                statusCheckID = UUID()
                assetStatus = .installed
            }
            return PreparedSpeechTarget(locale: locale, backend: key.backend)
        } catch {
            if selectedLanguage == key.language, selectedBackend == key.backend, !(error is CancellationError) {
                statusCheckID = UUID()
                switch error {
                case AppleSpeechAssetError.unsupportedLocale: assetStatus = .unsupportedLocale
                case AppleSpeechAssetError.unavailable: assetStatus = .unavailable
                default: assetStatus = .failed(error.localizedDescription)
                }
            }
            throw error
        }
    }

    private static var preferredLanguage: SpeechRecognitionLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferred == "zh-hant" || preferred.hasPrefix("zh-hant-") { return .chineseTraditional }
        if preferred == "zh" || preferred.hasPrefix("zh-") { return .chineseSimplified }
        return .englishUS
    }
}
