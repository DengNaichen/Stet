//
//  airTypeApp.swift
//  airType
//
//  Created by Naicheng Deng on 2026-03-09.
//

import SwiftUI

@main
struct airTypeApp: App {
    #if os(macOS)
    @StateObject private var macAppModel = MacAppModel()
    @StateObject private var appUpdateManager = AppUpdateManager()
    #endif

    var body: some Scene {
        #if os(macOS)
        MenuBarExtra("airType", systemImage: macAppModel.menuBarSymbolName) {
            MacMenuBarView()
                .environmentObject(macAppModel)
                .environmentObject(appUpdateManager)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsView()
                .environmentObject(macAppModel)
                .environmentObject(appUpdateManager)
        }

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
                Button("Quit airType") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}
