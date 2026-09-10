import Foundation

public struct HotkeyPreferences: Sendable {
    public let dictation: HotkeyPreference
    public let meeting: HotkeyPreference

    public init(
        dictation: HotkeyPreference = .dictation,
        meeting: HotkeyPreference = .meeting
    ) {
        self.dictation = dictation
        self.meeting = meeting
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

    public static let meeting = Self(
        id: "meeting",
        title: "Record Meeting"
    )
}
