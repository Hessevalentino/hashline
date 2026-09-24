import Foundation

/// YAML front matter: `---` on the first line up to a closing `---` or `...` line.
/// CommonMark would read it as a thematic break and a setext heading, so it is detected separately.
public struct FrontMatter: Equatable, Sendable {
    /// From the start of the document through the closing line (without its line break).
    public let range: NSRange
    /// The YAML between the delimiter lines.
    public let contentRange: NSRange

    /// Only the first 500 lines are searched for the closing delimiter.
    public static func detect(in text: NSString) -> FrontMatter? {
        guard text.hasPrefix("---") else { return nil }
        let first = text.lines(in: NSRange(location: 0, length: 0))[0]
        guard text.substring(with: first.content).trimmingCharacters(in: .whitespaces) == "---",
              first.terminator.length > 0 else { return nil }
        var location = NSMaxRange(first.terminator)
        var count = 0
        while location < text.length, count < 500 {
            let line = text.lines(in: NSRange(location: location, length: 0))[0]
            let trimmed = text.substring(with: line.content).trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." {
                let contentStart = NSMaxRange(first.terminator)
                let content = NSRange(location: contentStart, length: line.content.location - contentStart)
                return FrontMatter(range: NSRange(location: 0, length: NSMaxRange(line.content)), contentRange: content)
            }
            guard line.terminator.length > 0 else { break }
            location = NSMaxRange(line.terminator)
            count += 1
        }
        return nil
    }
}
