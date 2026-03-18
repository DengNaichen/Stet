//
//  StetApp.swift
//  Stet
//
//  Created by Naicheng Deng on 2026-03-09.
//

import SwiftUI
import AppKit

@main
struct StetApp: App {
    #if os(macOS)
    @StateObject private var macAppModel = MacAppModel()
    @StateObject private var appUpdateManager = AppUpdateManager()
    #endif

    var body: some Scene {
        #if os(macOS)
        MenuBarExtra("", systemImage: macAppModel.menuBarSymbolName) {
            MacMenuBarView()
                .environmentObject(macAppModel)
                .environmentObject(appUpdateManager)
        }
        .menuBarExtraStyle(.menu)

        Window("Settings", id: MacWindowSceneID.preferences) {
            MacSettingsView()
                .environmentObject(macAppModel)
                .environmentObject(appUpdateManager)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: MacUI.WindowMetrics.preferencesDefaultSize(for: NSScreen.main).width,
                     height: MacUI.WindowMetrics.preferencesDefaultSize(for: NSScreen.main).height)
        .windowResizability(.automatic)

        .commands {
            CommandMenu("Dictation") {
                Button(macAppModel.primaryButtonTitle) {
                    macAppModel.performPrimaryAction()
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Button(macAppModel.panelButtonTitle) {
                    macAppModel.togglePanel()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }

            MacUpdatesCommand(appUpdateManager: appUpdateManager)

            MacPreferencesCommand(appModel: macAppModel)
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
    let appModel: MacAppModel

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                appModel.openSettings {
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
