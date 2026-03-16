#if os(macOS)
import SwiftUI

struct MacHotkeySettingsView: View {
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MacHotKeySettingsSectionView(hotkey: .dictation) { shortcut in
                message = shortcut.map { "Shortcut updated to \($0)." } ?? "Shortcut cleared."
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
