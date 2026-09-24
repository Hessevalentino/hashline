import Foundation
import Markdown

/// A heading in the document outline.
public struct OutlineItem: Sendable, Hashable, Identifiable {
    public let level: Int
    public let title: String
    /// Range of the heading line in the document (UTF-16).
    public let range: NSRange

    public var id: Int { range.location }

    public init(level: Int, title: String, range: NSRange) {
        self.level = level
        self.title = title
        self.range = range
    }
}

/// Headings of a document, for the outline in the sidebar.
public enum DocumentOutline {
    /// With `text`, blocks inside YAML front matter are skipped (cmark reads its closing `---` as a
    /// setext underline).
    public static func items(in blocks: [MarkdownBlock], text: NSString? = nil) -> [OutlineItem] {
        let bodyStart = text.flatMap { FrontMatter.detect(in: $0) }.map { NSMaxRange($0.range) } ?? 0
        return blocks.compactMap { block in
            guard block.range.location >= bodyStart, let heading = block.markup as? Heading else { return nil }
            let title = heading.plainText.trimmingCharacters(in: .whitespaces)
            return OutlineItem(level: heading.level, title: title.isEmpty ? "Untitled" : title, range: block.range)
        }
    }

    /// Index of the heading whose section contains `offset` (the last heading at or before it).
    public static func currentIndex(in items: [OutlineItem], offset: Int) -> Int? {
        var low = 0, high = items.count - 1, found: Int?
        while low <= high {
            let middle = (low + high) / 2
            if items[middle].range.location <= offset {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return found
    }
}
