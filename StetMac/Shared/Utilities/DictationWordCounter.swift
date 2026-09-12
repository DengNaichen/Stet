#if os(macOS)
    import Foundation

    /// Speaking units used for Overview WPM after the display-unit cutover.
    ///
    /// Each Han/Hangul character counts as one unit and each Latin/digit token
    /// counts as one unit. English stays close to `NLTokenizer`; Chinese matches
    /// the one-character-one-word scores other speech apps show.
    enum DictationWordCounter {
        static func displayUnits(in text: String) -> Int {
            var count = 0
            var latin = ""

            func flushLatin() {
                guard !latin.isEmpty else { return }
                count += 1
                latin.removeAll(keepingCapacity: true)
            }

            for character in text {
                if isLatinTokenCharacter(character) {
                    latin.append(character)
                    continue
                }
                flushLatin()
                if character.isWhitespace || character.isPunctuation {
                    continue
                }
                if isDisplayCharacter(character) {
                    count += 1
                }
            }
            flushLatin()
            return count
        }

        private static func isDisplayCharacter(_ character: Character) -> Bool {
            character.unicodeScalars.contains { scalar in
                let value = scalar.value
                if scalar.properties.isIdeographic {
                    return true
                }
                return (0xAC00...0xD7AF).contains(value)
            }
        }

        private static func isLatinTokenCharacter(_ character: Character) -> Bool {
            if character.isASCII && (character.isLetter || character.isNumber || character == "'" || character == "’") {
                return true
            }
            return false
        }
    }
#endif
