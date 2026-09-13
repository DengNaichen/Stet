#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @Suite("Selected Calendar Store")
    struct SelectedCalendarStoreTests {
        @Test func defaultsToEmptyAndPersistsSortedUniqueIDs() throws {
            let suite = "SelectedCalendarStoreTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = SelectedCalendarStore(defaults: defaults, key: "selected")

            #expect(store.load().isEmpty)
            store.save(["work", "personal", "work"])

            #expect(store.load() == ["work", "personal"])
            #expect(defaults.stringArray(forKey: "selected") == ["personal", "work"])
        }
    }
#endif
