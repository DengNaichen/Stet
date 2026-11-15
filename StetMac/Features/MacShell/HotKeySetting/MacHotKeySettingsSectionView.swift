import KeyboardShortcuts
import SwiftUI

struct MacHotKeySettingsSectionView: View {
    let hotkey: HotkeyBinding
    var compactRow: Bool = false
    var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    init(
        hotkey: HotkeyBinding = .dictation,
        compactRow: Bool = false,
        onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil
    ) {
        self.hotkey = hotkey
        self.compactRow = compactRow
        self.onChange = onChange
    }

    var body: some View {
        if compactRow {
            LinearSettingRow(
                LocalizedStringKey(hotkey.title),
                subtitle: "Press a modifier-plus-key combination such as Control + Space or Command + K."
            ) {
                KeyboardShortcuts.Recorder(
                    for: hotkey.name,
                    onChange: { shortcut in
                        AnalyticsService.track("hotkey_changed")
                        onChange?(shortcut)
                    }
                )
            }
        } else {
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
}

#Preview {
    MacHotKeySettingsSectionView()
        .padding()
        .frame(width: 520)
}
