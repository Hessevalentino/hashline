import Foundation
import Markdown

/// Syntax element to colour in the source editor. Raw values are the element names
/// of MacDown `.style` themes, so those themes apply unchanged.
public enum HighlightToken: String, Sendable, CaseIterable {
    case heading1 = "H1", heading2 = "H2", heading3 = "H3", heading4 = "H4", heading5 = "H5", heading6 = "H6"
    case emphasis = "EMPH"
    case strong = "STRONG"
    case strikethrough = "STRIKE"
    case code = "CODE"
    case codeBlock = "VERBATIM"
    case link = "LINK"
    case autolink = "AUTO_LINK_URL"
    case image = "IMAGE"
    case listBullet = "LIST_BULLET"
    case listEnumerator = "LIST_ENUMERATOR"
    case blockquote = "BLOCKQUOTE"
    case horizontalRule = "HRULE"
    case comment = "COMMENT"
    case reference = "REFERENCE"

    static func heading(level: Int) -> HighlightToken {
        [.heading1, .heading2, .heading3, .heading4, .heading5, .heading6][min(max(level, 1), 6) - 1]
    }
}

public struct HighlightSpan: Equatable, Sendable {
    public let range: NSRange
    public let token: HighlightToken
}

/// Produces highlight spans for a block, outermost first, so inner spans override outer ones.
/// Markers (`#`, `**`, `[]()`) stay part of the span, as in MacDown.
public enum Highlighter {
    public static func spans(for block: MarkdownBlock, in text: NSString) -> [HighlightSpan] {
        var walker = SpanWalker(block: block, text: text)
        walker.visit(block.markup)
        return walker.spans
    }
}

private struct SpanWalker: MarkupWalker {
    let block: MarkdownBlock
    let text: NSString
    var spans: [HighlightSpan] = []
    /// Bounds from enclosing delimited spans: cmark reports a nested `*em*` that opens or closes
    /// together with its `**strong**` parent as spanning the parent's delimiters.
    private var limits: [NSRange] = []
    /// Autolinks are looked for only outside links.
    private var linkDepth = 0

    @discardableResult
    private mutating func add(_ node: Markup, _ token: HighlightToken) -> NSRange? {
        guard var range = block.range(of: node) else { return nil }
        if let limit = limits.last {
            let start = max(range.location, limit.location)
            let end = min(NSMaxRange(range), NSMaxRange(limit))
            range = NSRange(location: start, length: max(end - start, 0))
        }
        // Block ranges from cmark may include the trailing line break.
        while range.length > 0, isLineBreak(text.character(at: NSMaxRange(range) - 1)) { range.length -= 1 }
        guard range.length > 0 else { return nil }
        spans.append(HighlightSpan(range: range, token: token))
        return range
    }

    /// Adds a span for a delimited inline and visits its children within the closing delimiter.
    private mutating func addDelimited(_ node: Markup, _ token: HighlightToken, maxDelimiter: Int) {
        if let range = add(node, token) {
            let delimiter = min(delimiterLength(at: range.location), maxDelimiter)
            limits.append(NSRange(location: range.location + delimiter, length: max(range.length - 2 * delimiter, 0)))
            descendInto(node)
            limits.removeLast()
        } else {
            descendInto(node)
        }
    }

    private func delimiterLength(at location: Int) -> Int {
        guard location < text.length else { return 0 }
        let first = text.character(at: location)
        var length = 0
        while location + length < text.length, text.character(at: location + length) == first { length += 1 }
        return length
    }

    private func isLineBreak(_ unit: unichar) -> Bool {
        unit == 0x0A || unit == 0x0D
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        // `$$ … $$` display math: the whole paragraph is TeX.
        if paragraph.parent is Document, let source = block.source(of: paragraph),
           MathSyntax.displayMath(inParagraphSource: source) != nil {
            add(paragraph, .code)
            return
        }
        descendInto(paragraph)
    }

    mutating func visitHeading(_ heading: Heading) {
        add(heading, .heading(level: heading.level))
        descendInto(heading)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        addDelimited(emphasis, .emphasis, maxDelimiter: 1)
    }

    mutating func visitStrong(_ strong: Strong) {
        addDelimited(strong, .strong, maxDelimiter: 2)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        addDelimited(strikethrough, .strikethrough, maxDelimiter: 2)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        add(inlineCode, .code)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        add(codeBlock, .codeBlock)
    }

    mutating func visitLink(_ link: Link) {
        let isAutolink = link.childCount == 1 && (link.child(at: 0) as? Text)?.string == link.destination
        add(link, isAutolink ? .autolink : .link)
        linkDepth += 1
        descendInto(link)
        linkDepth -= 1
    }

    mutating func visitText(_ textNode: Text) {
        // GFM autolinks; only where the source is the literal text (no escapes or entities).
        guard linkDepth == 0, let textRange = block.range(of: textNode),
              textNode.string.contains(".") || textNode.string.contains("[^") || textNode.string.contains("$"),
              NSMaxRange(textRange) <= text.length, text.substring(with: textRange) == textNode.string else { return }
        for match in InlineExtensions.matches(in: textNode.string, settings: InlineExtensionSettings(math: true)) {
            let token: HighlightToken
            switch match.kind {
            case .autolink: token = .autolink
            case .footnote: token = .reference
            case .math: token = .code
            default: continue
            }
            spans.append(HighlightSpan(range: NSRange(location: textRange.location + match.range.location,
                                                      length: match.range.length), token: token))
        }
        if textNode.indexInParent == 0, textNode.parent is Paragraph,
           let definition = InlineExtensions.footnoteDefinition(in: textNode.string) {
            spans.append(HighlightSpan(range: NSRange(location: textRange.location, length: definition.prefixLength),
                                       token: .reference))
        }
    }

    mutating func visitImage(_ image: Image) {
        add(image, .image)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        add(blockQuote, .blockquote)
        descendInto(blockQuote)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        add(thematicBreak, .horizontalRule)
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        if html.rawHTML.hasPrefix("<!--") { add(html, .comment) }
    }

    mutating func visitInlineHTML(_ html: InlineHTML) {
        if html.rawHTML.hasPrefix("<!--") { add(html, .comment) }
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if let range = block.range(of: listItem), let marker = markerRange(of: listItem, at: range.location) {
            let token: HighlightToken = listItem.parent is OrderedList ? .listEnumerator : .listBullet
            spans.append(HighlightSpan(range: marker, token: token))
        }
        descendInto(listItem)
    }

    /// `-`, `*`, `+`, `1.` or `1)`, plus a task checkbox `[ ]` / `[x]` when present.
    private func markerRange(of item: ListItem, at start: Int) -> NSRange? {
        var end = start
        let length = text.length
        while end < length, !isSpace(text.character(at: end)) { end += 1 }
        guard end > start else { return nil }
        if item.checkbox != nil {
            var cursor = end
            while cursor < length, isSpace(text.character(at: cursor)) { cursor += 1 }
            if cursor + 2 < length, text.character(at: cursor) == 0x5B, text.character(at: cursor + 2) == 0x5D {
                end = cursor + 3
            }
        }
        return NSRange(location: start, length: end - start)
    }

    private func isSpace(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D
    }
}
