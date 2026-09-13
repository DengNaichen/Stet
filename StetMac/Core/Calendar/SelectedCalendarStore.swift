#if os(macOS)
    import Foundation

    nonisolated struct SelectedCalendarStore: @unchecked Sendable {
        static let defaultKey = MacPreferences.selectedCalendarIDs

        private let defaults: UserDefaults
        private let key: String

        init(defaults: UserDefaults = .standard, key: String = Self.defaultKey) {
            self.defaults = defaults
            self.key = key
        }

        func load() -> Set<String> {
            Set(defaults.stringArray(forKey: key) ?? [])
        }

        func save(_ calendarIDs: Set<String>) {
            defaults.set(calendarIDs.sorted(), forKey: key)
        }
    }
#endif
