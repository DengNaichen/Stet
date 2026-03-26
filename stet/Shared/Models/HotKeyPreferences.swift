import Foundation

struct HotkeyPreferences: Sendable {
    let dictation: HotkeyPreference

    init(dictation: HotkeyPreference = .dictation) {
        self.dictation = dictation
    }
}

struct HotkeyPreference: Hashable, Identifiable, Sendable {
    let id: String
    let title: String

    static let dictation = Self(
        id: "dictation",
        title: "Start Dictation"
    )
}
