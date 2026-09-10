import Foundation
import NaturalLanguage

public struct TextCorrection: Codable, Equatable, Sendable {
    public let original: String
    public let replacement: String

    public init(original: String, replacement: String) {
        self.original = original
        self.replacement = replacement
    }
}

/// Token replacement, not intent classification. Inputs must be the same dictation region.
public enum CorrectionExtractor {
    public enum ExtractionError: Error { case textTooLong, tooManyTokens }

    private struct Token {
        let text: String
        let start: Int
        let end: Int
        var isWord: Bool { text.unicodeScalars.contains(where: isAlphanumeric) }
    }

    public static func extract(original: String, edited: String) throws -> [TextCorrection] {
        guard original.unicodeScalars.count <= 32_000, edited.unicodeScalars.count <= 32_000 else {
            throw ExtractionError.textTooLong
        }
        let oldText = Array(original.precomposedStringWithCanonicalMapping.unicodeScalars)
        let newText = Array(edited.precomposedStringWithCanonicalMapping.unicodeScalars)
        var old = tokenize(oldText)
        var new = tokenize(newText)
        guard old.count <= 4096, new.count <= 4096 else { throw ExtractionError.tooManyTokens }
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix].text == new[prefix].text { prefix += 1 }
        var oldEnd = old.count
        var newEnd = new.count
        while oldEnd > prefix, newEnd > prefix, old[oldEnd - 1].text == new[newEnd - 1].text {
            oldEnd -= 1
            newEnd -= 1
        }
        old = Array(old[prefix..<oldEnd])
        new = Array(new[prefix..<newEnd])
        let matches = matchingBlocks(old.map { $0.text.lowercased() }, new.map { $0.text.lowercased() })
        var ranges: [(Range<Int>, Range<Int>)] = []
        var i = 0
        var j = 0
        for (a, b, length) in matches {
            if i < a, j < b { ranges.append((i..<a, j..<b)) }
            var start: Int?
            for offset in 0...length {
                let changed = offset < length && old[a + offset].text != new[b + offset].text
                if changed, start == nil { start = offset }
                if !changed, let first = start {
                    ranges.append(((a + first)..<(a + offset), (b + first)..<(b + offset)))
                    start = nil
                }
            }
            i = a + length
            j = b + length
        }
        return ranges.compactMap { oldRange, newRange in
            let oldWords = old[oldRange].filter(\.isWord)
            let newWords = new[newRange].filter(\.isWord)
            guard let firstOld = oldWords.first, let lastOld = oldWords.last,
                let firstNew = newWords.first, let lastNew = newWords.last
            else { return nil }
            return TextCorrection(
                original: string(oldText[firstOld.start..<lastOld.end]),
                replacement: string(newText[firstNew.start..<lastNew.end])
            )
        }
    }

    // Same longest contiguous match and earliest-a/earliest-b tie breaking as
    // the Python reference with autojunk disabled. No edit-distance threshold.
    private static func matchingBlocks(_ a: [String], _ b: [String]) -> [(Int, Int, Int)] {
        var positions: [String: [Int]] = [:]
        for (index, word) in b.enumerated() { positions[word, default: []].append(index) }
        var pending = [(0, a.count, 0, b.count)]
        var blocks: [(Int, Int, Int)] = []
        while let (alo, ahi, blo, bhi) = pending.popLast() {
            var bestA = alo
            var bestB = blo
            var bestSize = 0
            var previous: [Int: Int] = [:]
            for i in alo..<ahi {
                var lengths: [Int: Int] = [:]
                for j in positions[a[i], default: []] where j >= blo && j < bhi {
                    let length = previous[j - 1, default: 0] + 1
                    lengths[j] = length
                    if length > bestSize {
                        bestA = i - length + 1
                        bestB = j - length + 1
                        bestSize = length
                    }
                }
                previous = lengths
            }
            guard bestSize > 0 else { continue }
            blocks.append((bestA, bestB, bestSize))
            if alo < bestA, blo < bestB { pending.append((alo, bestA, blo, bestB)) }
            if bestA + bestSize < ahi, bestB + bestSize < bhi {
                pending.append((bestA + bestSize, ahi, bestB + bestSize, bhi))
            }
        }
        blocks.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        var merged: [(Int, Int, Int)] = []
        for block in blocks {
            if let last = merged.last, last.0 + last.2 == block.0, last.1 + last.2 == block.1 {
                merged[merged.count - 1] = (last.0, last.1, last.2 + block.2)
            } else {
                merged.append(block)
            }
        }
        merged.append((a.count, b.count, 0))
        return merged
    }

    private static func tokenize(_ text: [Unicode.Scalar]) -> [Token] {
        var result: [Token] = []
        var index = 0
        while index < text.count {
            if CharacterSet.whitespacesAndNewlines.contains(text[index]) { index += 1; continue }
            let start = index
            let character = text[index]
            index += 1
            if isAlphanumeric(character), isCJK(character) {
                while index < text.count, isAlphanumeric(text[index]), isCJK(text[index]) { index += 1 }
                let run = string(text[start..<index])
                let tokenizer = NLTokenizer(unit: .word)
                tokenizer.setLanguage(.simplifiedChinese)
                tokenizer.string = run
                for range in tokenizer.tokens(for: run.startIndex..<run.endIndex) {
                    result.append(
                        Token(
                            text: String(run[range]),
                            start: start + run.unicodeScalars.distance(from: run.startIndex, to: range.lowerBound),
                            end: start + run.unicodeScalars.distance(from: run.startIndex, to: range.upperBound)
                        ))
                }
                continue
            }
            var wordStart = isWordCharacter(character)
            if ".@#".unicodeScalars.contains(character), index < text.count, isWordCharacter(text[index]) {
                wordStart = start == 0 || !isAlphanumeric(text[start - 1]) || isCJK(text[start - 1])
            }
            if wordStart {
                while index < text.count {
                    let current = text[index]
                    if isWordCharacter(current) {
                        index += 1
                    } else if ".-'’/".unicodeScalars.contains(current), index + 1 < text.count,
                        isWordCharacter(text[index + 1])
                    {
                        index += 1
                    } else if "+#".unicodeScalars.contains(current) {
                        index += 1
                    } else {
                        break
                    }
                }
            }
            result.append(Token(text: string(text[start..<index]), start: start, end: index))
        }
        return result
    }

    private static func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        String(String.UnicodeScalarView(scalars))
    }

    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
            .decimalNumber, .letterNumber, .otherNumber:
            return true
        default: return false
        }
    }

    private static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
        guard !isCJK(scalar) else { return false }
        return isAlphanumeric(scalar) || scalar == "_"
            || [.nonspacingMark, .spacingMark, .enclosingMark].contains(scalar.properties.generalCategory)
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (0x3400...0x4DBF).contains(value) || (0x4E00...0x9FFF).contains(value)
            || (0xF900...0xFAFF).contains(value) || (0x20000...0x323AF).contains(value)
            || (0x3040...0x30FF).contains(value) || (0x31F0...0x31FF).contains(value)
    }
}
