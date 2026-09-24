#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @Suite("Hot-word learning review store")
    struct HotwordLearningReviewStoreTests {
        @Test func suggestionsAreDeduplicatedAndResolvedTermsStaySuppressed() throws {
            let suite = "hotword-review-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = HotwordLearningReviewStore(defaults: defaults)

            #expect(store.addSuggestions(["Cursor", " cursor ", "Stet"]) == ["Cursor", "Stet"])
            #expect(store.addSuggestions(["Cursor"]).isEmpty)
            store.keep(["Cursor"])
            store.exclude(["Stet"])

            #expect(store.pendingTerms().isEmpty)
            #expect(store.excludedTerms() == ["Stet"])
            #expect(store.addSuggestions(["Cursor", "Stet"]).isEmpty)
        }
    }
#endif
