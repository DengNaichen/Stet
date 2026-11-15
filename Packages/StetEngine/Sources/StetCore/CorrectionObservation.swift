import Foundation

public struct CorrectionEditPair: Equatable, Sendable {
    public let original: String
    public let edited: String

    public init(original: String, edited: String) {
        self.original = original
        self.edited = edited
    }
}

/// Tracks a single verified dictation paste and settles at most once when editing ends.
public struct CorrectionObservation: Sendable {
    public enum Result: Equatable, Sendable {
        case waiting
        case evaluate(CorrectionEditPair)
        case finished
    }

    public static let verificationTimeout: TimeInterval = 2
    public static let observationWindow: TimeInterval = 30
    private static let clearGraceInterval: TimeInterval = 0.5

    private let prefix: String
    private let suffix: String
    private let inserted: String
    private let expected: String
    private let startedAt: TimeInterval
    private var verified = false
    private var ended = false
    private var latestRegion: String?
    private var clearedAt: TimeInterval?

    public init?(before: String, selection: NSRange, inserted: String, startedAt: TimeInterval) {
        guard before.utf16.count <= 64_000,
            inserted.unicodeScalars.count <= 32_000,
            !inserted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let range = Self.validRange(selection, in: before)
        else { return nil }
        prefix = String(before[..<range.lowerBound])
        suffix = String(before[range.upperBound...])
        self.inserted = inserted
        expected = prefix + inserted + suffix
        self.startedAt = startedAt
    }

    public mutating func sample(_ field: String, at time: TimeInterval) -> Result {
        guard !ended else { return .finished }
        guard time >= startedAt else {
            ended = true
            return .finished
        }
        if time - startedAt > Self.observationWindow {
            return finish(triggeredByCompletionKey: false, at: time)
        }
        guard field.utf16.count <= 96_000 else {
            ended = true
            return .finished
        }

        if !verified {
            guard field.utf16.elementsEqual(expected.utf16) else {
                if time - startedAt >= Self.verificationTimeout {
                    ended = true
                    return .finished
                }
                return .waiting
            }
            verified = true
            latestRegion = inserted
            clearedAt = nil
            return .waiting
        }

        if let region = extractRegion(from: field) {
            if region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return recordEmptyState(at: time)
            }
            latestRegion = region
            clearedAt = nil
            return .waiting
        }

        if field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return recordEmptyState(at: time)
        }

        // User moved outside the dictated bookmarks and edited surrounding text;
        // settle whatever valid edit was already captured inside the bookmarks.
        return finish(triggeredByCompletionKey: false, at: time)
    }

    public mutating func finish(
        currentField: String? = nil,
        triggeredByCompletionKey: Bool = false,
        at time: TimeInterval
    ) -> Result {
        guard !ended else { return .finished }
        guard time >= startedAt else {
            ended = true
            return .finished
        }

        if let currentField, time - startedAt <= Self.observationWindow, currentField.utf16.count <= 96_000 {
            if !verified {
                if currentField.utf16.elementsEqual(expected.utf16) {
                    verified = true
                    latestRegion = inserted
                }
            } else if let region = extractRegion(from: currentField),
                !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                latestRegion = region
                clearedAt = nil
            } else if !triggeredByCompletionKey,
                currentField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                ended = true
                return .finished
            }
        }

        ended = true
        guard verified else { return .finished }

        if let clearedAt {
            // Without Return/Enter/Tab, an emptied field means the user deleted or undid the dictation.
            guard triggeredByCompletionKey, time - clearedAt < Self.clearGraceInterval else {
                return .finished
            }
        }

        guard let edited = latestRegion,
            Self.shouldEvaluate(original: inserted, edited: edited)
        else {
            return .finished
        }

        return .evaluate(CorrectionEditPair(original: inserted, edited: edited))
    }

    public static func shouldEvaluate(original: String, edited: String) -> Bool {
        let orig = original.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let edit = edited.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !orig.isEmpty, !edit.isEmpty, orig != edit else { return false }
        guard orig.unicodeScalars.count <= 32_000, edit.unicodeScalars.count <= 32_000 else {
            return false
        }

        let origSubstantive = substantiveScalars(of: orig)
        let editSubstantive = substantiveScalars(of: edit)
        guard !editSubstantive.isEmpty, origSubstantive != editSubstantive else {
            return false
        }

        if isPureDeletion(original: orig, edited: edit) {
            return false
        }

        if isPureTrailingAppend(original: orig, edited: edit) {
            return false
        }

        return true
    }

    private mutating func recordEmptyState(at time: TimeInterval) -> Result {
        if let clearedAt {
            if time - clearedAt >= Self.clearGraceInterval {
                ended = true
                return .finished
            }
        } else {
            clearedAt = time
        }
        return .waiting
    }

    private func extractRegion(from field: String) -> String? {
        let prefixCount = prefix.utf16.count
        let suffixCount = suffix.utf16.count
        guard field.utf16.count >= prefixCount + suffixCount,
            field.utf16.starts(with: prefix.utf16),
            field.utf16.suffix(suffixCount).elementsEqual(suffix.utf16),
            let range = Self.validRange(
                NSRange(location: prefixCount, length: field.utf16.count - prefixCount - suffixCount),
                in: field
            )
        else { return nil }
        return String(field[range])
    }

    private static func substantiveScalars(of text: String) -> [Unicode.Scalar] {
        let scalars = Array(text.unicodeScalars)
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(scalars.count)

        for (index, scalar) in scalars.enumerated() {
            if isAlphanumeric(scalar) || isCombiningMark(scalar) || "+#@_".unicodeScalars.contains(scalar) {
                result.append(scalar)
            } else if scalar == ".", index + 1 < scalars.count, isAlphanumeric(scalars[index + 1]) {
                result.append(scalar)
            }
        }
        return result
    }

    private static func isPureDeletion(original: String, edited: String) -> Bool {
        if original.contains(edited) {
            return true
        }
        let origScalars = Array(original.unicodeScalars)
        let editScalars = Array(edited.unicodeScalars)
        guard editScalars.count < origScalars.count else { return false }

        var prefixLen = 0
        while prefixLen < editScalars.count, origScalars[prefixLen] == editScalars[prefixLen] {
            prefixLen += 1
        }
        var suffixLen = 0
        while suffixLen < editScalars.count - prefixLen,
            origScalars[origScalars.count - 1 - suffixLen] == editScalars[editScalars.count - 1 - suffixLen]
        {
            suffixLen += 1
        }

        guard prefixLen + suffixLen == editScalars.count else { return false }
        // Deleting extra characters inside a single Latin/identifier token ("Pythhon" -> "Python")
        // forms a repaired word and should still be evaluated.
        if prefixLen > 0, prefixLen < editScalars.count,
            isNonCJKWordScalar(editScalars[prefixLen - 1]),
            isNonCJKWordScalar(editScalars[prefixLen])
        {
            return false
        }
        return true
    }

    private static func isPureTrailingAppend(original: String, edited: String) -> Bool {
        guard edited.hasPrefix(original) else { return false }
        let origScalars = Array(original.unicodeScalars)
        let editScalars = Array(edited.unicodeScalars)
        guard editScalars.count > origScalars.count,
            let origLast = origScalars.last
        else { return false }

        let tail = editScalars[origScalars.count...]
        guard let tailFirst = tail.first else { return false }

        // Completing a single trailing Latin/identifier token ("Pytho" -> "Python") is a repair,
        // provided no whitespace was appended after it.
        if isNonCJKWordScalar(origLast),
            isNonCJKWordScalar(tailFirst),
            !tail.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) })
        {
            return false
        }
        return true
    }

    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
            .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    private static func isCombiningMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }

    private static func isNonCJKWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        guard !isCJK(scalar) else { return false }
        return isAlphanumeric(scalar) || scalar == "_" || isCombiningMark(scalar)
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (0x3400...0x4DBF).contains(value) || (0x4E00...0x9FFF).contains(value)
            || (0xF900...0xFAFF).contains(value) || (0x20000...0x323AF).contains(value)
            || (0x3040...0x30FF).contains(value) || (0x31F0...0x31FF).contains(value)
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
