//
//  StetApp.swift
//  Stet
//
//  Created by Naicheng Deng on 2026-03-09.
//

import SwiftUI

@main
struct StetApp: App {
    #if os(macOS)
    @StateObject private var macAppModel = MacAppModel()
    @StateObject private var appUpdateManager = AppUpdateManager()
    #endif

    var body: some Scene {
        #if os(macOS)
        MenuBarExtra("Stet", systemImage: macAppModel.menuBarSymbolName) {
            MacMenuBarView()
                .environmentObject(macAppModel)
                .environmentObject(appUpdateManager)
        }
        .menuBarExtraStyle(.window)

        Window("Stet", id: MacWindowSceneID.preferences) {
            MacSettingsView()
                .environmentObject(macAppModel)
                .environmentObject(appUpdateManager)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentMinSize)

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

            CommandGroup(replacing: .appTermination) {
                Button("Quit Stet") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }

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
#endif
