#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Mac Appearance Settings View Model", .serialized)
    struct MacAppearanceSettingsViewModelTests {
        @Test func loadReadsStoredTheme() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(MacDictationVisualTheme.autumn.rawValue, forKey: MacPreferences.shaderTheme)
            let viewModel = MacAppearanceSettingsViewModel(defaults: defaults)

            viewModel.load()

            #expect(viewModel.shaderTheme == .autumn)
        }

        @Test func themeChangesPersistAfterLoad() {
            let defaults = TestSupport.makeUserDefaults()
            let viewModel = MacAppearanceSettingsViewModel(defaults: defaults)

            viewModel.load()
            viewModel.shaderTheme = .autumn

            #expect(defaults.string(forKey: MacPreferences.shaderTheme) == MacDictationVisualTheme.autumn.rawValue)
        }
    }
#endif
