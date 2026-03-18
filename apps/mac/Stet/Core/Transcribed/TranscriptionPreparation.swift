import Foundation
import Speech

enum OnDeviceSpeechPreparation {
    static func resolveSupportedLocale(for locale: Locale) async throws -> Locale {
        if let equivalent = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            return equivalent
        }

        throw SpeechServiceError.unsupportedLocale
    }

    static func ensureAssets(locale: Locale) async throws -> Locale {
        let supportedLocale = try await resolveSupportedLocale(for: locale)
        let transcriber = DictationTranscriber(locale: supportedLocale, preset: .progressiveLongDictation)
        try await ensureAssets(for: transcriber)
        return supportedLocale
    }

    static func ensureAssets(for transcriber: DictationTranscriber) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])

        switch status {
        case .installed:
            return
        case .unsupported:
            throw SpeechServiceError.unsupportedLocale
        case .supported, .downloading:
            if let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await installationRequest.downloadAndInstall()
            }
        @unknown default:
            throw SpeechServiceError.failedToStart
        }
    }
}
