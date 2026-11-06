#if os(macOS)
    import Foundation
    import StetCore

    struct HotwordLearningReviewStore: Sendable {
        private enum Key {
            static let pending = "hotword.learning.pending.v1"
            static let kept = "hotword.learning.kept.v1"
            static let excluded = "hotword.learning.excluded.v1"
        }

        private let defaults: UserDefaults

        init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
        }

        func pendingTerms() -> [String] { values(for: Key.pending) }
        func excludedTerms() -> [String] { values(for: Key.excluded) }

        @discardableResult
        func addSuggestions(_ terms: [String]) -> [String] {
            let existing = pendingTerms()
            let blocked = Set((values(for: Key.kept) + excludedTerms()).map(normalize))
            let existingKeys = Set(existing.map(normalize))
            let additions = normalizedTerms(terms).filter {
                !blocked.contains(normalize($0)) && !existingKeys.contains(normalize($0))
            }
            guard !additions.isEmpty else { return [] }
            defaults.set(existing + additions, forKey: Key.pending)
            NotificationCenter.default.post(name: .hotwordLearningReviewDidChange, object: nil)
            return additions
        }

        func exclude(_ terms: [String]) {
            move(terms, from: Key.pending, to: Key.excluded)
        }

        func keep(_ terms: [String]) {
            move(terms, from: Key.pending, to: Key.kept)
        }

        private func move(_ terms: [String], from source: String, to destination: String) {
            let keys = Set(terms.map(normalize))
            defaults.set(values(for: source).filter { !keys.contains(normalize($0)) }, forKey: source)
            let merged = normalizedTerms(values(for: destination) + terms)
            defaults.set(merged, forKey: destination)
            NotificationCenter.default.post(name: .hotwordLearningReviewDidChange, object: nil)
        }

        private func values(for key: String) -> [String] {
            defaults.stringArray(forKey: key) ?? []
        }

        private func normalizedTerms(_ terms: [String]) -> [String] {
            var seen = Set<String>()
            return terms.compactMap { term in
                let normalized = term.precomposedStringWithCanonicalMapping
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                guard !normalized.isEmpty, seen.insert(normalize(normalized)).inserted else { return nil }
                return normalized
            }
        }

        private func normalize(_ term: String) -> String {
            term.precomposedStringWithCanonicalMapping
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .lowercased()
        }
    }

    extension Notification.Name {
        static let hotwordLearningReviewDidChange = Notification.Name("hotwordLearningReviewDidChange")
    }
#endif
