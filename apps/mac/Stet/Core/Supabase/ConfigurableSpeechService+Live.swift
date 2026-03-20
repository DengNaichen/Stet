import Foundation

extension ConfigurableSpeechService {
    static func live(
        settingsStore: DictationSettingsStore = DictationSettingsStore(),
        locale: Locale = .autoupdatingCurrent,
        captureService: (any AudioCaptureService)? = nil
    ) -> ConfigurableSpeechService {
        let resolvedCaptureService = captureService ?? MacAudioCaptureService()

        return ConfigurableSpeechService(
            settingsStore: settingsStore,
            locale: locale,
            pipelineFactory: .live(
                relayAuthenticationContext: {
                    await SupabaseService.shared.relayAuthenticationContext()
                }
            ),
            captureService: resolvedCaptureService
        )
    }
}
