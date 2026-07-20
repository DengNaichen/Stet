import Foundation

public struct HotkeyPreferences: Sendable {
    public let dictation: HotkeyPreference

    public init(dictation: HotkeyPreference = .dictation) {
        self.dictation = dictation
    }
}

public struct HotkeyPreference: Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    public static let dictation = Self(
        id: "dictation",
        title: "Start Dictation"
    )
}
