import Foundation

/// One replacement in the text plus the selection afterwards. Every editing command produces
/// exactly one, so each command is a single undo step.
public struct TextEdit: Equatable, Sendable {
    /// Range to replace, in the text before the edit (UTF-16).
    public let range: NSRange
    public let replacement: String
    /// Selection after the edit, in the text after the edit.
    public let selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// Applies the edit to a string (tests, previews of the result).
    public func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

extension NSString {
    func character(atOffset offset: Int) -> Character? {
        guard offset >= 0, offset < length else { return nil }
        return Character(substring(with: rangeOfComposedCharacterSequence(at: offset)))
    }

    /// Lines covered by `range`, each without its line break, with the break kept separately.
    func lines(in range: NSRange) -> [(content: NSRange, terminator: NSRange)] {
        var result: [(NSRange, NSRange)] = []
        var location = lineRange(for: NSRange(location: range.location, length: 0)).location
        let end = NSMaxRange(lineRange(for: range))
        repeat {
            var start = 0, lineEnd = 0, contentsEnd = 0
            getLineStart(&start, end: &lineEnd, contentsEnd: &contentsEnd,
                         for: NSRange(location: location, length: 0))
            result.append((NSRange(location: start, length: contentsEnd - start),
                           NSRange(location: contentsEnd, length: lineEnd - contentsEnd)))
            location = lineEnd
        } while location < end
        return result
    }
}

extension String {
    /// The string after the first `offset` UTF-16 units.
    func utf16Suffix(from offset: Int) -> String {
        (self as NSString).substring(from: min(offset, (self as NSString).length))
    }
}
