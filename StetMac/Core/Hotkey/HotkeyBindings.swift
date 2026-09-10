import Foundation
import StetCore
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

    static let meeting = Self(
        preference: .meeting,
        name: .meetingRecordingHotkey
    )
}

extension KeyboardShortcuts.Name {
    static let dictationHotkey = Self(
        "\(HotkeyPreference.dictation.id)Hotkey",
        default: .init(.period, modifiers: [.command])
    )

    static let meetingRecordingHotkey = Self(
        "\(HotkeyPreference.meeting.id)Hotkey",
        default: .init(.m, modifiers: [.control, .option, .command])
    )
}
