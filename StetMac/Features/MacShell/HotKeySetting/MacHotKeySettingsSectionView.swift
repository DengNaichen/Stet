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
        VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
            LabeledContent(LocalizedStringKey(hotkey.title)) {
                KeyboardShortcuts.Recorder(
                    for: hotkey.name,
                    onChange: { shortcut in
                        AnalyticsService.track("hotkey_changed")
                        onChange?(shortcut)
                    }
                )
                .frame(width: MacUI.SettingsViewMetrics.controlWidth, alignment: .trailing)
            }

            Text(
                "Use a modifier-plus-key shortcut, for example Control + Space or Command + K. Two plain character keys will not register here."
            )
            .font(MacUI.Typography.caption)
            .foregroundStyle(MacUI.Foreground.secondary)
        }
    }
}

#Preview {
    MacHotKeySettingsSectionView()
        .padding()
        .frame(width: 520)
}
