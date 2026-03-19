import Foundation

extension ConfigurableSpeechService {
    nonisolated static func live(
        settingsStore: DictationSettingsStore = DictationSettingsStore(),
        locale: Locale = .autoupdatingCurrent,
        captureService: (any AudioCaptureService)? = nil
    ) -> ConfigurableSpeechService {
        ConfigurableSpeechService(
            settingsStore: settingsStore,
            locale: locale,
            pipelineFactory: .live(
                relayAuthenticationContext: {
                    await SupabaseService.shared.relayAuthenticationContext()
                }
            ),
            captureService: captureService
        )
    }
}
