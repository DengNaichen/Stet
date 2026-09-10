import Foundation

/// A short-lived, verified insertion. It never treats a key press as proof of sending.
public struct CorrectionObservation: Sendable {
    public enum Result: Equatable, Sendable {
        case waiting
        case learn([TextCorrection])
        case finished
    }

    private let prefix: String
    private let suffix: String
    private let inserted: String
    private let expected: String
    private let startedAt: TimeInterval
    private var verified = false
    private var ended = false
    private var candidate: String?
    private var changedAt: TimeInterval = 0
    private var learned: String?

    public init?(before: String, selection: NSRange, inserted: String, startedAt: TimeInterval) {
        guard before.utf16.count <= 64_000, inserted.unicodeScalars.count <= 32_000,
            !inserted.isEmpty, let range = Self.validRange(selection, in: before)
        else { return nil }
        prefix = String(before[..<range.lowerBound])
        suffix = String(before[range.upperBound...])
        self.inserted = inserted
        expected = prefix + inserted + suffix
        self.startedAt = startedAt
    }

    public mutating func sample(_ field: String, at time: TimeInterval, finishing: Bool = false) -> Result {
        guard !ended else { return .finished }
        guard time >= startedAt, time - startedAt <= 30, field.utf16.count <= 96_000 else {
            ended = true
            return .finished
        }
        if !verified {
            guard field.utf16.elementsEqual(expected.utf16) else {
                if finishing || time - startedAt >= 2 { ended = true; return .finished }
                return .waiting
            }
            verified = true
            candidate = inserted
            changedAt = time
        }
        let prefixCount = prefix.utf16.count
        let suffixCount = suffix.utf16.count
        guard field.utf16.count >= prefixCount + suffixCount,
            field.utf16.starts(with: prefix.utf16),
            field.utf16.suffix(suffixCount).elementsEqual(suffix.utf16),
            let range = Self.validRange(
                NSRange(location: prefixCount, length: field.utf16.count - prefixCount - suffixCount), in: field)
        else { ended = true; return .finished }
        let region = String(field[range])
        if region != candidate { candidate = region; changedAt = time }
        if finishing { ended = true }
        guard finishing || time - changedAt >= 1 else { return .waiting }
        guard region != inserted, region != learned else { return finishing ? .finished : .waiting }
        do {
            let corrections = try CorrectionExtractor.extract(original: inserted, edited: region)
            learned = region
            return corrections.isEmpty ? (finishing ? .finished : .waiting) : .learn(corrections)
        } catch {
            ended = true
            return .finished
        }
    }

    private static func validRange(_ range: NSRange, in text: String) -> Range<String.Index>? {
        guard range.location >= 0, range.length >= 0, range.location <= text.utf16.count,
            range.length <= text.utf16.count - range.location
        else { return nil }
        let lower = text.utf16.index(text.utf16.startIndex, offsetBy: range.location)
        let upper = text.utf16.index(lower, offsetBy: range.length)
        guard let start = lower.samePosition(in: text.unicodeScalars),
            let end = upper.samePosition(in: text.unicodeScalars)
        else { return nil }
        return start..<end
    }
}
