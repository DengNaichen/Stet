#if os(macOS)
import Foundation
import Testing

@testable import Stet

@MainActor
private final class TestMacGeneralSettingsAppModel: MacGeneralSettingsAppModeling {
    var launchAtLoginChanges: [Bool] = []
    var dockVisibilityChanges: [Bool] = []
    var refreshRuntimeCallCount = 0
    var setLaunchAtLoginError: (any Error)?
    var onSetLaunchAtLogin: ((Bool) -> Void)?

    func setLaunchAtLoginEnabled(_ enabled: Bool) throws {
        if let setLaunchAtLoginError {
            throw setLaunchAtLoginError
        }

        launchAtLoginChanges.append(enabled)
        onSetLaunchAtLogin?(enabled)
    }

    func refreshRuntimeFromSettings() {
        refreshRuntimeCallCount += 1
    }

    func applyDockVisibility(showInDock: Bool) {
        dockVisibilityChanges.append(showInDock)
    }
}

@MainActor
@Suite("Mac General Settings View Model", .serialized)
struct MacGeneralSettingsViewModelTests {
    private func makeViewModel(
        defaults: UserDefaults,
        launchAtLoginIsEnabled: @escaping @MainActor () -> Bool = { false },
        exportConfiguration: @escaping @MainActor (DictationSettingsStore) throws -> Void = { _ in },
        importConfiguration: @escaping @MainActor (DictationSettingsStore) throws -> Void = { _ in }
    ) -> MacGeneralSettingsViewModel {
        MacGeneralSettingsViewModel(
            settingsStore: DictationSettingsStore(
                defaults: defaults,
                secretStore: TestSecretStore()
            ),
            defaults: defaults,
            dependencies: .init(
                launchAtLoginIsEnabled: launchAtLoginIsEnabled,
                exportConfiguration: exportConfiguration,
                importConfiguration: importConfiguration
            )
        )
    }

    @Test func loadStateReflectsManagedSettings() {
        let defaults = TestSupport.makeUserDefaults()
        let viewModel = makeViewModel(
            defaults: defaults,
            launchAtLoginIsEnabled: { true }
        )

        let state = viewModel.loadState()

        #expect(state.launchAtLogin)
        #expect(state.showInDock == false)
    }

    @Test func shaderThemeLoadsAndPersistsPreference() {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(MacDictationVisualTheme.midnight.rawValue, forKey: MacPreferences.shaderTheme)
        let viewModel = makeViewModel(defaults: defaults)

        viewModel.load()

        #expect(viewModel.shaderTheme == .midnight)

        viewModel.shaderTheme = .forest

        #expect(defaults.string(forKey: MacPreferences.shaderTheme) == MacDictationVisualTheme.forest.rawValue)
    }

    @Test func importConfigurationRefreshesRuntimeAndReturnsImportedState() {
        let defaults = TestSupport.makeUserDefaults()
        var runtimeLaunchAtLogin = false
        let appModel = TestMacGeneralSettingsAppModel()
        appModel.onSetLaunchAtLogin = { runtimeLaunchAtLogin = $0 }
        let viewModel = makeViewModel(
            defaults: defaults,
            launchAtLoginIsEnabled: { runtimeLaunchAtLogin },
            importConfiguration: { _ in
                defaults.set(true, forKey: MacPreferences.launchAtLogin)
                defaults.set(true, forKey: MacPreferences.showInDock)
            }
        )

        let state = viewModel.importConfiguration(appModel: appModel)

        #expect(appModel.launchAtLoginChanges == [true])
        #expect(appModel.refreshRuntimeCallCount == 1)
        #expect(state.launchAtLogin)
        #expect(state.showInDock)
        #expect(
            viewModel.feedback?.message
                == "Configuration imported. API keys are still managed separately in Keychain."
        )
        #expect(viewModel.feedback?.isError == false)
    }

    @Test func importConfigurationRollsBackLaunchAtLoginWhenRuntimeUpdateFails() {
        let defaults = TestSupport.makeUserDefaults()
        var runtimeLaunchAtLogin = false
        let appModel = TestMacGeneralSettingsAppModel()
        appModel.setLaunchAtLoginError = TestError.expected
        let viewModel = makeViewModel(
            defaults: defaults,
            launchAtLoginIsEnabled: { runtimeLaunchAtLogin },
            importConfiguration: { _ in
                defaults.set(true, forKey: MacPreferences.launchAtLogin)
            }
        )

        let state = viewModel.importConfiguration(appModel: appModel)

        #expect(state.launchAtLogin == false)
        #expect(defaults.object(forKey: MacPreferences.launchAtLogin) as? Bool == false)
        #expect(appModel.refreshRuntimeCallCount == 1)
        #expect(viewModel.feedback?.message == TestError.expected.localizedDescription)
        #expect(viewModel.feedback?.isError == true)
    }

    @Test func applyLaunchAtLoginChangePersistsSuccessAndRollsBackFailure() {
        let defaults = TestSupport.makeUserDefaults()
        let successAppModel = TestMacGeneralSettingsAppModel()
        let viewModel = makeViewModel(defaults: defaults)

        let successValue = viewModel.applyLaunchAtLoginChange(
            oldValue: false,
            newValue: true,
            appModel: successAppModel
        )

        #expect(successValue)
        #expect(defaults.object(forKey: MacPreferences.launchAtLogin) as? Bool == true)
        #expect(viewModel.feedback?.message == "Launch at Login enabled.")
        #expect(viewModel.feedback?.isError == false)

        let failingAppModel = TestMacGeneralSettingsAppModel()
        failingAppModel.setLaunchAtLoginError = TestError.expected

        let rolledBackValue = viewModel.applyLaunchAtLoginChange(
            oldValue: false,
            newValue: true,
            appModel: failingAppModel
        )

        #expect(rolledBackValue == false)
        #expect(defaults.object(forKey: MacPreferences.launchAtLogin) as? Bool == false)
        #expect(viewModel.feedback?.message == TestError.expected.localizedDescription)
        #expect(viewModel.feedback?.isError == true)
    }

    @Test func applyDockVisibilityChangePersistsPreferenceAndDelegatesToAppModel() {
        let defaults = TestSupport.makeUserDefaults()
        let appModel = TestMacGeneralSettingsAppModel()
        let viewModel = makeViewModel(defaults: defaults)

        viewModel.applyDockVisibilityChange(true, appModel: appModel)

        #expect(defaults.object(forKey: MacPreferences.showInDock) as? Bool == true)
        #expect(appModel.dockVisibilityChanges == [true])
        #expect(viewModel.feedback?.message == "Dock icon enabled.")
        #expect(viewModel.feedback?.isError == false)
    }
}
#endif
