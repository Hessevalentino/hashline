import Foundation

/// Words, characters, lines and reading time, for the status bar.
public struct TextStatistics: Equatable, Sendable {
    public let words: Int
    public let characters: Int
    public let lines: Int

    /// Minutes at 200 words per minute, at least 1 for non-empty text.
    public var readingMinutes: Int { words == 0 ? 0 : max(1, Int((Double(words) / 200).rounded())) }

    /// One linear pass over UTF-16: a word starts where a letter or digit follows anything else;
    /// characters count grapheme clusters approximately (combining marks and the second half of a
    /// surrogate pair do not count); lines count line breaks plus one.
    public static func of(_ text: NSString) -> TextStatistics {
        let length = text.length
        guard length > 0 else { return TextStatistics(words: 0, characters: 0, lines: 0) }
        var words = 0
        var characters = 0
        var lines = 1
        var inWord = false
        let chunk = 4_096
        var buffer = [unichar](repeating: 0, count: chunk)
        var location = 0
        var previousWasCR = false
        while location < length {
            let count = min(chunk, length - location)
            text.getCharacters(&buffer, range: NSRange(location: location, length: count))
            for index in 0..<count {
                let unit = buffer[index]
                if unit == 0x0A {
                    if !previousWasCR { lines += 1 }
                } else if unit == 0x0D {
                    lines += 1
                }
                previousWasCR = unit == 0x0D
                let isLowSurrogate = unit >= 0xDC00 && unit <= 0xDFFF
                let isCombining = unit >= 0x0300 && unit <= 0x036F
                if !isLowSurrogate && !isCombining { characters += 1 }
                var isWordUnit = isWordCharacter(unit)
                if unit >= 0xD800, unit <= 0xDBFF, index + 1 < count {
                    // A pair outside the BMP: letters (e.g. rare CJK) count, emoji do not.
                    let value = 0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(buffer[index + 1]) - 0xDC00)
                    isWordUnit = UnicodeScalar(value).map { CharacterSet.alphanumerics.contains($0) } ?? false
                }
                if isWordUnit && !inWord { words += 1 }
                if !isLowSurrogate { inWord = isWordUnit || (inWord && isCombining) }
            }
            location += count
        }
        return TextStatistics(words: words, characters: characters, lines: lines)
    }

    private static func isWordCharacter(_ unit: unichar) -> Bool {
        if unit < 0x80 {
            return (unit >= 0x30 && unit <= 0x39) || (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)
                || unit == 0x5F || unit == 0x27
        }
        // Letters of other scripts (Czech, Cyrillic, CJK…), excluding punctuation and spaces.
        guard let scalar = UnicodeScalar(unit) else { return false }  // surrogate: decided by the caller
        return CharacterSet.alphanumerics.contains(scalar)
    }
}
