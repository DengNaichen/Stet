#if os(macOS)
import SwiftUI

struct MacHotkeySettingsView: View {
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                MacHotKeySettingsSectionView(hotkey: .dictation) { shortcut in
                    message = shortcut.map { "Shortcut updated to \($0)." } ?? "Shortcut cleared."
                }
            } header: {
                Text("Shortcut Engine")
            }
            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }
}
#endif
