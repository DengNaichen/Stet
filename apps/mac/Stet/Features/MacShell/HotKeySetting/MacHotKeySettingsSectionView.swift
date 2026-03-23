import SwiftUI
import KeyboardShortcuts

struct MacHotKeySettingsSectionView: View {
    let hotkey: HotkeyBinding
    var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    init(
        hotkey: HotkeyBinding = .dictation,
        onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil
    ) {
        self.hotkey = hotkey
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledContent(hotkey.title) {
                KeyboardShortcuts.Recorder(
                    for: hotkey.name,
                    onChange: onChange
                )
                .frame(width: 240, alignment: .trailing)
            }

            Text("Use a modifier-plus-key shortcut, for example Control + Space or Command + K. Two plain character keys will not register here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    MacHotKeySettingsSectionView()
        .padding()
        .frame(width: 520)
}
