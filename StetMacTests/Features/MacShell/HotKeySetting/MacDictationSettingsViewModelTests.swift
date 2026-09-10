#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Mac Dictation Settings View Model", .serialized)
    struct MacDictationSettingsViewModelTests {
        @Test func dictationCompletionNotificationTogglePersists() {
            let defaults = TestSupport.makeUserDefaults()
            let viewModel = MacDictationSettingsViewModel(defaults: defaults)

            viewModel.load()
            viewModel.dictationCompletionNotificationsEnabled = false

            #expect(
                defaults.object(forKey: MacPreferences.dictationCompletionNotificationsEnabled) as? Bool
                    == false)
        }

        @Test func interactionSoundsAndMuteTogglesPersist() {
            let defaults = TestSupport.makeUserDefaults()
            let viewModel = MacDictationSettingsViewModel(defaults: defaults)

            viewModel.load()
            viewModel.interactionSoundsEnabled = false
            viewModel.pauseMediaDuringDictation = true

            #expect(defaults.object(forKey: MacPreferences.interactionSoundsEnabled) as? Bool == false)
            #expect(defaults.object(forKey: MacPreferences.pauseMediaDuringDictation) as? Bool == true)
        }

        @Test func loadUsesStoredDefaultsWithoutWritingUntilChanged() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(false, forKey: MacPreferences.interactionSoundsEnabled)
            defaults.set(true, forKey: MacPreferences.pauseMediaDuringDictation)
            defaults.set(false, forKey: MacPreferences.dictationCompletionNotificationsEnabled)

            let viewModel = MacDictationSettingsViewModel(defaults: defaults)
            viewModel.load()

            #expect(!viewModel.interactionSoundsEnabled)
            #expect(viewModel.pauseMediaDuringDictation)
            #expect(!viewModel.dictationCompletionNotificationsEnabled)
        }
    }
#endif
