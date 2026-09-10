#if os(macOS)
    import Combine
    import Foundation

    @MainActor
    final class MacDictationSettingsViewModel: ObservableObject {
        @Published var pauseMediaDuringDictation = false {
            didSet {
                guard hasLoadedPreferences else { return }
                defaults.set(pauseMediaDuringDictation, forKey: MacPreferences.pauseMediaDuringDictation)
            }
        }
        @Published var interactionSoundsEnabled = true {
            didSet {
                guard hasLoadedPreferences else { return }
                defaults.set(interactionSoundsEnabled, forKey: MacPreferences.interactionSoundsEnabled)
            }
        }
        @Published var dictationCompletionNotificationsEnabled = true {
            didSet {
                guard hasLoadedPreferences else { return }
                defaults.set(
                    dictationCompletionNotificationsEnabled,
                    forKey: MacPreferences.dictationCompletionNotificationsEnabled
                )
                if dictationCompletionNotificationsEnabled {
                    Task {
                        await MacDictationCompletionNotificationService.shared.requestAuthorizationIfNeeded()
                    }
                }
            }
        }

        private let defaults: UserDefaults
        private var hasLoadedPreferences = false

        init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
        }

        func load() {
            hasLoadedPreferences = false
            pauseMediaDuringDictation =
                defaults.object(forKey: MacPreferences.pauseMediaDuringDictation) as? Bool ?? false
            interactionSoundsEnabled = defaults.object(forKey: MacPreferences.interactionSoundsEnabled) as? Bool ?? true
            dictationCompletionNotificationsEnabled =
                defaults.object(forKey: MacPreferences.dictationCompletionNotificationsEnabled) as? Bool ?? true
            hasLoadedPreferences = true
        }

        func previewSound() {
            InteractionSoundPlayer().playPreview(preset: .defaultPreset)
        }
    }
#endif
