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

            #expect(viewModel.shaderTheme == .autumn)
            #expect(viewModel.appliedShaderTheme == .autumn)
        }

        @Test func updateShaderThemeWithPersistWritesTheme() {
            let defaults = TestSupport.makeUserDefaults()
            let viewModel = MacAppearanceSettingsViewModel(defaults: defaults)

            viewModel.updateShaderTheme(.autumn, persist: true)

            #expect(defaults.string(forKey: MacPreferences.shaderTheme) == MacDictationVisualTheme.autumn.rawValue)
            #expect(viewModel.hasAppliedSelectedTheme)
        }

        @Test func updateShaderThemeWithoutPersistKeepsPendingSelection() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(MacDictationVisualTheme.egg.rawValue, forKey: MacPreferences.shaderTheme)
            let viewModel = MacAppearanceSettingsViewModel(defaults: defaults)

            viewModel.updateShaderTheme(.autumn, persist: false)

            #expect(viewModel.shaderTheme == .autumn)
            #expect(viewModel.appliedShaderTheme == .egg)
            #expect(defaults.string(forKey: MacPreferences.shaderTheme) == MacDictationVisualTheme.egg.rawValue)
            #expect(viewModel.hasAppliedSelectedTheme == false)
        }

        @Test func applySelectedThemePersistsPendingSelection() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(MacDictationVisualTheme.egg.rawValue, forKey: MacPreferences.shaderTheme)
            let viewModel = MacAppearanceSettingsViewModel(defaults: defaults)

            viewModel.updateShaderTheme(.autumn, persist: false)
            viewModel.applySelectedTheme()

            #expect(defaults.string(forKey: MacPreferences.shaderTheme) == MacDictationVisualTheme.autumn.rawValue)
            #expect(viewModel.appliedShaderTheme == .autumn)
            #expect(viewModel.hasAppliedSelectedTheme)
        }
    }
#endif
