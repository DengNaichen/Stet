import Foundation
import AppKit
import KeyboardShortcuts

struct HotkeyBinding: Hashable, Sendable {
    let preference: HotkeyPreference
    let name: KeyboardShortcuts.Name

    var title: String {
        preference.title
    }

    static let dictation = Self(
        preference: .dictation,
        name: .dictationHotkey
    )
}

extension KeyboardShortcuts.Name {
    static let dictationHotkey = Self(
        "\(HotkeyPreference.dictation.id)Hotkey",
        default: .init(.period, modifiers: [.command])
    )
}
