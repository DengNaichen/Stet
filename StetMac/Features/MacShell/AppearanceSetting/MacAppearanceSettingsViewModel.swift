#if os(macOS)
    import Combine
    import Foundation

    @MainActor
    final class MacAppearanceSettingsViewModel: ObservableObject {
        static let shared = MacAppearanceSettingsViewModel()

        @Published private(set) var shaderTheme = MacDictationVisualTheme.egg
        @Published private(set) var appliedShaderTheme = MacDictationVisualTheme.egg

        private let defaults: UserDefaults

        init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
            load()
        }

        func load() {
            let storedTheme = MacDictationVisualTheme.fromStoredValue(
                defaults.string(forKey: MacPreferences.shaderTheme)
            )
            shaderTheme = storedTheme
            appliedShaderTheme = storedTheme
        }

        func updateShaderTheme(_ theme: MacDictationVisualTheme, persist: Bool) {
            shaderTheme = theme

            if persist {
                applySelectedTheme()
            }
        }

        func applySelectedTheme() {
            defaults.set(shaderTheme.rawValue, forKey: MacPreferences.shaderTheme)
            appliedShaderTheme = shaderTheme
        }

        var hasAppliedSelectedTheme: Bool {
            shaderTheme == appliedShaderTheme
        }
    }
#endif
