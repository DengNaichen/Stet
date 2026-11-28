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

    var supportsAutoDetectEnglish: Bool {
        self == .chineseSimplified || self == .chineseTraditional
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
    struct PreparedSpeechTarget: Sendable, Equatable {
        let language: SpeechRecognitionLanguage
        let locale: Locale
        let backend: SpeechTranscriberBackend
    }

    struct PreparedRoutingTargets: Sendable, Equatable {
        let primary: PreparedSpeechTarget
        let secondary: PreparedSpeechTarget?
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
            if let secondary = secondaryLanguage,
                secondary == selectedLanguage || secondary.voxLinguaCode == selectedLanguage.voxLinguaCode
            {
                secondaryLanguage = nil
            }
            statusCheckID = UUID()
            assetStatus = .checking
        }
    }

    @Published var secondaryLanguage: SpeechRecognitionLanguage? {
        didSet {
            let normalized: SpeechRecognitionLanguage? =
                if let candidate = secondaryLanguage,
                    candidate != selectedLanguage,
                    candidate.voxLinguaCode != selectedLanguage.voxLinguaCode
                {
                    candidate
                } else {
                    nil
                }
            if secondaryLanguage != normalized {
                secondaryLanguage = normalized
                return
            }
            guard secondaryLanguage != oldValue else { return }
            if let secondaryLanguage {
                defaults.set(secondaryLanguage.rawValue, forKey: Self.secondaryLanguageKey)
                secondaryStatusCheckID = UUID()
                secondaryAssetStatus = .checking
            } else {
                defaults.removeObject(forKey: Self.secondaryLanguageKey)
                secondaryStatusCheckID = UUID()
                secondaryAssetStatus = nil
            }
        }
    }

    @Published var selectedBackend: SpeechTranscriberBackend {
        didSet {
            guard selectedBackend != oldValue else { return }
            defaults.set(selectedBackend.rawValue, forKey: Self.backendKey)
            statusCheckID = UUID()
            assetStatus = .checking
            if secondaryLanguage != nil {
                secondaryStatusCheckID = UUID()
                secondaryAssetStatus = .checking
            }
        }
    }

    @Published private(set) var assetStatus: SpeechAssetStatus = .checking
    @Published private(set) var secondaryAssetStatus: SpeechAssetStatus?

    private static let languageKey = "dictation.speechRecognitionLanguage"
    private static let secondaryLanguageKey = "dictation.speechSecondaryLanguage"
    private static let backendKey = "dictation.speechTranscriberBackend"
    private let defaults: UserDefaults
    private var statusCheckID = UUID()
    private var secondaryStatusCheckID = UUID()
    private var installations: [AssetKey: Task<Locale, any Error>] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let primary =
            defaults.string(forKey: Self.languageKey).flatMap(SpeechRecognitionLanguage.init(rawValue:))
            ?? Self.preferredLanguage
        selectedLanguage = primary
        if let rawSecondary = defaults.string(forKey: Self.secondaryLanguageKey),
            let parsed = SpeechRecognitionLanguage(rawValue: rawSecondary),
            parsed != primary,
            parsed.voxLinguaCode != primary.voxLinguaCode
        {
            secondaryLanguage = parsed
            secondaryAssetStatus = .checking
        } else {
            secondaryLanguage = nil
            secondaryAssetStatus = nil
        }
        selectedBackend =
            defaults.string(forKey: Self.backendKey).flatMap(SpeechTranscriberBackend.init(rawValue:))
            ?? .speechTranscriber
    }

    func refreshAssetStatus() async {
        await refreshPrimaryAssetStatus()
        await refreshSecondaryAssetStatus()
    }

    func downloadAssetIfNeeded() async throws {
        _ = try await prepareTarget()
        if let secondary = secondaryLanguage {
            _ = try? await prepareTarget(for: secondary, backend: selectedBackend)
        }
        await reconcileReservedLocales()
    }

    func downloadSecondaryAssetIfNeeded() async {
        guard let secondary = secondaryLanguage else { return }
        _ = try? await prepareTarget(for: secondary, backend: selectedBackend)
        await reconcileReservedLocales()
    }

    func resolvedLocale() async throws -> Locale {
        try await Self.resolve(selectedLanguage, backend: selectedBackend)
    }

    func prepareLocale() async throws -> Locale {
        try await prepareTarget().locale
    }

    func prepareTarget() async throws -> PreparedSpeechTarget {
        try await prepareTarget(for: selectedLanguage, backend: selectedBackend)
    }

    /// Freezes the active backend and resolves primary + optional secondary targets for a session.
    /// Primary installation is mandatory; secondary is strictly non-fatal and degrades to `nil`
    /// when unavailable, uninstalled (when `allowSecondaryDownload == false`), or over quota.
    func prepareRoutingTargets(allowSecondaryDownload: Bool) async throws -> PreparedRoutingTargets {
        let backend = selectedBackend
        let primaryLanguage = selectedLanguage
        let secondaryCandidate = secondaryLanguage

        let primary = try await prepareTarget(for: primaryLanguage, backend: backend)

        var resolvedSecondary: PreparedSpeechTarget?
        if let secondaryCandidate,
            secondaryCandidate != primaryLanguage,
            secondaryCandidate.voxLinguaCode != primaryLanguage.voxLinguaCode
        {
            if allowSecondaryDownload {
                resolvedSecondary = try? await prepareTarget(for: secondaryCandidate, backend: backend)
            } else {
                resolvedSecondary = await installedTargetIfReady(for: secondaryCandidate, backend: backend)
            }
        }

        if allowSecondaryDownload {
            await reconcileReservedLocales()
        }

        return PreparedRoutingTargets(
            primary: primary,
            secondary: resolvedSecondary,
            backend: backend
        )
    }

    private func refreshPrimaryAssetStatus() async {
        let key = AssetKey(language: selectedLanguage, backend: selectedBackend)
        guard installations[key] == nil else { return }
        let checkID = UUID()
        statusCheckID = checkID

        let status = await Self.queryAssetStatus(for: key)
        guard statusCheckID == checkID, !Task.isCancelled else { return }
        assetStatus = status
    }

    private func refreshSecondaryAssetStatus() async {
        guard let secondary = secondaryLanguage else {
            secondaryAssetStatus = nil
            return
        }
        let key = AssetKey(language: secondary, backend: selectedBackend)
        guard installations[key] == nil else { return }
        let checkID = UUID()
        secondaryStatusCheckID = checkID

        let status = await Self.queryAssetStatus(for: key)
        guard secondaryStatusCheckID == checkID, !Task.isCancelled else { return }
        secondaryAssetStatus = status
    }

    private func installedTargetIfReady(
        for language: SpeechRecognitionLanguage,
        backend: SpeechTranscriberBackend
    ) async -> PreparedSpeechTarget? {
        do {
            let locale = try await Self.resolve(language, backend: backend)
            let modules = Self.makeModules(locale: locale, backend: backend)
            guard await AssetInventory.status(forModules: modules) == .installed else {
                return nil
            }
            return PreparedSpeechTarget(language: language, locale: locale, backend: backend)
        } catch {
            return nil
        }
    }

    private func prepareTarget(
        for language: SpeechRecognitionLanguage,
        backend: SpeechTranscriberBackend
    ) async throws -> PreparedSpeechTarget {
        try Task.checkCancellation()
        let key = AssetKey(language: language, backend: backend)
        if let installation = installations[key] {
            let locale = try await installation.value
            try Task.checkCancellation()
            return PreparedSpeechTarget(language: language, locale: locale, backend: backend)
        }

        if language == selectedLanguage && backend == selectedBackend {
            statusCheckID = UUID()
        } else if language == secondaryLanguage && backend == selectedBackend {
            secondaryStatusCheckID = UUID()
        }

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
        return PreparedSpeechTarget(language: language, locale: locale, backend: backend)
    }

    /// Best-effort reconciliation of `AssetInventory` locale reservations against the active pair.
    /// Never throws so quota limits on a secondary locale never fail primary dictation bootstrap.
    private func reconcileReservedLocales() async {
        var desiredLocales: [Locale] = []
        if let primaryLocale = try? await Self.resolve(selectedLanguage, backend: selectedBackend) {
            desiredLocales.append(primaryLocale)
        }
        if let secondary = secondaryLanguage,
            let secondaryLocale = try? await Self.resolve(secondary, backend: selectedBackend)
        {
            desiredLocales.append(secondaryLocale)
        }
        guard !desiredLocales.isEmpty else { return }

        let desiredIDs = Set(desiredLocales.map(\.identifier))
        let existingReserved = await AssetInventory.reservedLocales
        for reserved in existingReserved where !desiredIDs.contains(reserved.identifier) {
            _ = await AssetInventory.release(reservedLocale: reserved)
        }

        let remainingReserved = await AssetInventory.reservedLocales
        let reservedIDs = Set(remainingReserved.map(\.identifier))
        let maxAllowed = AssetInventory.maximumReservedLocales
        var currentCount = remainingReserved.count

        for locale in desiredLocales where !reservedIDs.contains(locale.identifier) {
            guard currentCount < maxAllowed else { break }
            if (try? await AssetInventory.reserve(locale: locale)) == true {
                currentCount += 1
            }
        }
    }

    private func publish(_ status: SpeechAssetStatus, for key: AssetKey) {
        guard selectedBackend == key.backend else { return }
        if selectedLanguage == key.language, assetStatus != status {
            assetStatus = status
        }
        if secondaryLanguage == key.language, secondaryAssetStatus != status {
            secondaryAssetStatus = status
        }
    }

    private static func queryAssetStatus(for key: AssetKey) async -> SpeechAssetStatus {
        do {
            let locale = try await resolve(key.language, backend: key.backend)
            let modules = makeModules(locale: locale, backend: key.backend)
            return assetStatus(for: await AssetInventory.status(forModules: modules))
        } catch {
            return .unsupported
        }
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
