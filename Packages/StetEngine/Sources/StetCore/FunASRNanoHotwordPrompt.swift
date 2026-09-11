import Foundation

/// Caps the Fun-ASR Nano hotword prompt so a large glossary cannot overflow
/// the 512-token prefix batch. Rewrite still receives the full dictionary.
public enum FunASRNanoHotwordPrompt: Sendable {
    public static let maximumTermCount = 50
    public static let maximumJoinedCharacterCount = 400

    public static func selectedTerms(from records: [GlossaryEntry]) -> [String] {
        let ordered =
            records.filter { $0.source == .manual } + records.filter { $0.source != .manual }
        var selected: [String] = []
        var joined = ""
        for record in ordered {
            let next = selected.isEmpty ? record.term : joined + ", " + record.term
            guard next.count <= maximumJoinedCharacterCount else { continue }
            selected.append(record.term)
            joined = next
            if selected.count == maximumTermCount { break }
        }
        return selected
    }

    public static func makePrompt(from records: [GlossaryEntry]) -> String? {
        let terms = selectedTerms(from: records)
        guard !terms.isEmpty else { return nil }
        return terms.joined(separator: ", ")
    }

    public static func records(from preferredSpellings: [String]) -> [GlossaryEntry] {
        preferredSpellings.map { GlossaryEntry(term: $0, source: .manual) }
    }
}
