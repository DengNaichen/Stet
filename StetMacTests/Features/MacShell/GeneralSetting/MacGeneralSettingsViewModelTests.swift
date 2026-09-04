#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    private final class TestMacGeneralSettingsAppModel: MacGeneralSettingsAppModeling {
        var launchAtLoginChanges: [Bool] = []
        var dockVisibilityChanges: [Bool] = []
        var setLaunchAtLoginError: (any Error)?
        var isDebugForceOnboardingEnabled = false

        func setLaunchAtLoginEnabled(_ enabled: Bool) throws {
            if let setLaunchAtLoginError {
                throw setLaunchAtLoginError
            }

            launchAtLoginChanges.append(enabled)
        }

        func refreshRuntimeFromSettings() {
        }

        func applyDockVisibility(showInDock: Bool) {
            dockVisibilityChanges.append(showInDock)
        }

        func setDebugForceOnboardingEnabled(_ enabled: Bool) {
            isDebugForceOnboardingEnabled = enabled
        }

        func resetOnboardingForDebug() {
            isDebugForceOnboardingEnabled = false
        }
    }

    @MainActor
    @Suite("Mac General Settings View Model", .serialized)
    struct MacGeneralSettingsViewModelTests {
        private func makeViewModel(
            defaults: UserDefaults,
            launchAtLoginIsEnabled: @escaping @MainActor () -> Bool = { false }
        ) -> MacGeneralSettingsViewModel {
            MacGeneralSettingsViewModel(
                defaults: defaults,
                dependencies: .init(
                    launchAtLoginIsEnabled: launchAtLoginIsEnabled
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

        @Test func dictationCompletionNotificationTogglePersists() {
            let defaults = TestSupport.makeUserDefaults()
            let viewModel = makeViewModel(defaults: defaults)

            viewModel.load()
            viewModel.dictationCompletionNotificationsEnabled = false

            #expect(
                defaults.object(forKey: MacPreferences.dictationCompletionNotificationsEnabled) as? Bool
                    == false)
        }
    }
#endif
