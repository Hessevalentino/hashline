import Foundation

/// Limits how deeply a document can nest before it reaches the parser. swift-markdown converts
/// cmark's tree recursively, and so do the highlighter and the renderer; a hostile file with
/// thousands of nested quotes, list levels or emphasis runs overflows the stack and crashes the
/// app (and Quick Look). Nesting beyond `limit` is neutralised by replacing the excess markers with
/// spaces: ASCII for ASCII, so every UTF-8 and UTF-16 position stays where it was and the block map,
/// highlighting and preview keep working on the original text. Real documents never get close.
public enum NestingGuard {
    public static let limit = 32

    /// The text to parse: `text` itself when nothing is too deep.
    public static func defused(_ text: String) -> String {
        var scanner = Scanner(bytes: Array(text.utf8))
        guard scanner.bytes.count > limit else { return text }
        scanner.defuseLinePrefixes()
        scanner.defuseInlineOpeners()
        guard scanner.changed, let result = String(bytes: scanner.bytes, encoding: .utf8) else { return text }
        return result
    }

    private struct Scanner {
        var bytes: [UInt8]
        var changed = false

        static let space = UInt8(ascii: " ")
        static let digits = UInt8(ascii: "0")...UInt8(ascii: "9")

        mutating func blank(_ index: Int) {
            bytes[index] = Self.space
            changed = true
        }

        func isBlank(_ index: Int) -> Bool {
            index >= bytes.count || isWhitespace(bytes[index])
        }

        func isWhitespace(_ byte: UInt8) -> Bool {
            byte == Self.space || byte == UInt8(ascii: "\t") || isLineEnd(byte)
        }

        func isLineEnd(_ byte: UInt8) -> Bool {
            byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
        }

        func isPunctuation(_ byte: UInt8) -> Bool {
            (0x21...0x2F).contains(byte) || (0x3A...0x40).contains(byte) || (0x5B...0x60).contains(byte)
                || (0x7B...0x7E).contains(byte)
        }

        // MARK: Block containers

        /// Quote and list markers at the start of each line, and list depth through indentation.
        mutating func defuseLinePrefixes() {
            var index = 0
            while index < bytes.count {
                let end = defusePrefix(from: index)
                var next = end
                while next < bytes.count, !isLineEnd(bytes[next]) { next += 1 }
                index = next + 1
            }
        }

        /// Walks one line's container prefix; returns where it ends.
        private mutating func defusePrefix(from start: Int) -> Int {
            var containers = 0
            var column = 0
            var position = start
            while position < bytes.count {
                let byte = bytes[position]
                if byte == Self.space {
                    column += 1
                } else if byte == UInt8(ascii: "\t") {
                    column += 4 - column % 4
                } else if let markerEnd = markerEnd(at: position) {
                    containers += 1
                    // Deep indentation nests lists across lines even with one marker per line.
                    if containers > limit || (byte != UInt8(ascii: ">") && column > 2 * limit) { blank(markerEnd) }
                    column += markerEnd - position + 1
                    position = markerEnd
                } else {
                    break
                }
                position += 1
            }
            return position
        }

        /// The last byte of a container marker starting at `position` (`>`, `-`, `*`, `+`, `12.`, `3)`).
        private func markerEnd(at position: Int) -> Int? {
            let byte = bytes[position]
            if byte == UInt8(ascii: ">") { return position }
            if [UInt8(ascii: "-"), UInt8(ascii: "*"), UInt8(ascii: "+")].contains(byte) {
                return isBlank(position + 1) ? position : nil
            }
            guard Self.digits.contains(byte) else { return nil }
            var end = position
            while end < bytes.count, end - position < 9, Self.digits.contains(bytes[end]) { end += 1 }
            guard end < bytes.count, bytes[end] == UInt8(ascii: ".") || bytes[end] == UInt8(ascii: ")"),
                  isBlank(end + 1) else { return nil }
            return end
        }

        // MARK: Inline

        /// Emphasis and link openers that are never closed nest one inside another. The balance is
        /// counted per paragraph (a blank line resets it); openers beyond the limit become spaces.
        mutating func defuseInlineOpeners() {
            var emphasis = 0
            var brackets = 0
            var index = 0
            var lineIsBlank = true
            while index < bytes.count {
                let byte = bytes[index]
                if isLineEnd(byte) {
                    if lineIsBlank { (emphasis, brackets) = (0, 0) }
                    lineIsBlank = true
                } else if !isWhitespace(byte) {
                    lineIsBlank = false
                }
                switch byte {
                case UInt8(ascii: "\\"):
                    index += 2  // an escaped character is never a delimiter
                    continue
                case UInt8(ascii: "*"), UInt8(ascii: "_"), UInt8(ascii: "~"):
                    index = defuseDelimiterRun(at: index, balance: &emphasis)
                    continue
                case UInt8(ascii: "["):
                    if brackets >= limit { blank(index) } else { brackets += 1 }
                case UInt8(ascii: "]"):
                    brackets = max(0, brackets - 1)
                default:
                    break
                }
                index += 1
            }
        }

        /// One run of the same delimiter (CommonMark flanking rules, simplified); returns its end.
        private mutating func defuseDelimiterRun(at start: Int, balance: inout Int) -> Int {
            var end = start
            while end < bytes.count, bytes[end] == bytes[start] { end += 1 }
            let before = start > 0 ? bytes[start - 1] : Self.space
            let after = end < bytes.count ? bytes[end] : Self.space
            let opens = !isWhitespace(after) && (isWhitespace(before) || isPunctuation(before) || !isPunctuation(after))
            let closes = !isWhitespace(before)
                && (isWhitespace(after) || isPunctuation(after) || !isPunctuation(before))
            let length = end - start
            if opens && !closes {
                let allowed = max(0, 2 * limit - balance)
                if length > allowed {
                    for position in (start + allowed)..<end { blank(position) }
                }
                balance += min(length, allowed)
            } else if closes && !opens {
                balance = max(0, balance - length)
            }
            return end
        }
    }
}
