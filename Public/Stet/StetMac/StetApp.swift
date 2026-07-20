//
//  StetApp.swift
//  Stet
//
//  Created by Naicheng Deng on 2026-03-09.
//

import SwiftUI
import AppKit
import StetVisuals

@main
struct StetApp: App {
    #if os(macOS)
        @StateObject private var appModel: MacAppModel
        @StateObject private var dictationCommandsViewModel: MacDictationCommandsViewModel
        @StateObject private var settingsShellViewModel: MacSettingsShellViewModel
        @StateObject private var appUpdateManager = AppUpdateManager()

        init() {
            AnalyticsService.initialize()
            let appModel = MacAppModel()
            _appModel = StateObject(wrappedValue: appModel)
            _dictationCommandsViewModel = StateObject(
                wrappedValue: MacDictationCommandsViewModel(coordinator: appModel)
            )
            _settingsShellViewModel = StateObject(
                wrappedValue: MacSettingsShellViewModel(coordinator: appModel)
            )
        }
    #endif

    var body: some Scene {
        #if os(macOS)
            MenuBarExtra("", image: "menuBarIcon") {
                MacMenuBarView()
                    .environmentObject(settingsShellViewModel)
                    .environmentObject(appUpdateManager)
                    .onOpenURL { url in
                        appModel.handleDeepLink(url)
                    }
            }
            .menuBarExtraStyle(.menu)

            Window("Settings", id: MacWindowSceneID.preferences) {
                MacSettingsView()
                    .environmentObject(settingsShellViewModel)
                    .environmentObject(appUpdateManager)
            }
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)
            .defaultSize(
                width: MacUI.WindowMetrics.preferencesDefaultSize(for: NSScreen.main).width,
                height: MacUI.WindowMetrics.preferencesDefaultSize(for: NSScreen.main).height
            )
            .windowResizability(.automatic)

            Window("Shader Debug", id: MacWindowSceneID.shaderDebug) {
                MacDictationShaderWorkbenchView()
            }
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)
            .defaultSize(width: 1180, height: 820)
            .windowResizability(.automatic)

            .commands {
                CommandMenu("Dictation") {
                    Button(dictationCommandsViewModel.primaryButtonTitle) {
                        dictationCommandsViewModel.performPrimaryAction()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])

                    Button(dictationCommandsViewModel.panelButtonTitle) {
                        dictationCommandsViewModel.togglePanel()
                    }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                }

                MacUpdatesCommand(appUpdateManager: appUpdateManager)

                MacPreferencesCommand(settingsShellViewModel: settingsShellViewModel)
            }
        #else
            WindowGroup {
                ContentView()
            }
        #endif
    }
}

#if os(macOS)
    private struct MacPreferencesCommand: Commands {
        @Environment(\.openWindow) private var openWindow
        let settingsShellViewModel: MacSettingsShellViewModel

        var body: some Commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    settingsShellViewModel.openSettings {
                        openWindow(id: MacWindowSceneID.preferences)
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    private struct MacUpdatesCommand: Commands {
        @ObservedObject var appUpdateManager: AppUpdateManager

        var body: some Commands {
            CommandGroup(after: .appSettings) {
                Button(updateMenuTitle) {
                    appUpdateManager.checkForUpdates()
                }
                .disabled(appUpdateManager.isChecking || !appUpdateManager.canCheckForUpdates)
            }
        }

        private var updateMenuTitle: String {
            switch appUpdateManager.state {
            case .updateAvailable(_, let latestVersion):
                return "Update Available (\(latestVersion))"
            case .checking:
                return "Checking for Updates…"
            case .unavailable:
                return "Updates Unavailable"
            default:
                return "Check for Updates…"
            }
        }
    }
#endif
