#if os(macOS)
    import Combine
    import Foundation

    @MainActor
    final class MacAppearanceSettingsViewModel: ObservableObject {
        @Published var shaderTheme = MacDictationVisualTheme.egg {
            didSet {
                guard hasLoadedPreferences else { return }
                defaults.set(shaderTheme.rawValue, forKey: MacPreferences.shaderTheme)
            }
        }

        private let defaults: UserDefaults
        private var hasLoadedPreferences = false

        init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
        }

        func load() {
            hasLoadedPreferences = false
            shaderTheme = MacDictationVisualTheme.fromStoredValue(
                defaults.string(forKey: MacPreferences.shaderTheme)
            )
            hasLoadedPreferences = true
        }
    }
#endif
