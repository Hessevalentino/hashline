import Foundation
import Markdown

/// The single Markdown → HTML renderer (preview, HTML/PDF export, Quick Look).
/// Output follows the CommonMark reference renderer so spec tests apply.
/// Raw HTML is passed through; sanitisation is a separate step (F10).
public enum HTMLRenderer {
    /// HTML of one top-level block. With `id`, the outermost element carries `data-block`.
    /// Extensions beyond the CommonMark reference output (off by default, so spec tests apply).
    public struct Options: Sendable {
        /// Colour fenced code with highlight.js.
        public var highlightCode = false
        /// GFM autolinks for bare `www.`/`http(s)://`/e-mail text.
        public var autolinks = false
        /// Task checkboxes without `disabled`, numbered per block (`data-task`), for the preview.
        public var interactiveTasks = false
        /// `id` anchors on headings (for `[toc]` and links to sections).
        public var headingIDs = false
        /// Footnote references and definitions; `footnoteTexts` feeds the reference tooltips.
        public var footnotes = false
        public var footnoteTexts: [String: String] = [:]
        /// `:shortcode:` emoji.
        public var emoji = false
        /// Raw HTML through the allow-list sanitizer.
        public var sanitizeHTML = false
        /// Optional `==mark==`, `^sup^`, `~sub~`.
        public var extensions = InlineExtensionSettings()
        /// Mermaid code blocks become `<div class="mermaid-diagram">` placeholders the preview renders.
        public var mermaid = false
        /// Base for relative image paths; with it, local images load through `hashline-asset:` and
        /// images get `loading="lazy"`.
        public var imageBase: URL?
        public var resolveImages = false
        /// Headings for `[toc]`; nil leaves `[toc]` as text.
        public var tableOfContents: [TableOfContents.Entry]?
        /// Summary of the collapsed front matter in the preview (localized by the app).
        public var frontMatterLabel = "Front matter"
        /// Rendered Mermaid diagrams (source → SVG) for export; the SVG replaces the placeholder.
        public var diagrams: [String: String] = [:]

        public init(highlightCode: Bool = false, autolinks: Bool = false, interactiveTasks: Bool = false) {
            self.highlightCode = highlightCode
            self.autolinks = autolinks
            self.interactiveTasks = interactiveTasks
        }

        /// Everything the preview shows; extensions and document-level data are set by the caller.
        public static var preview: Options {
            var options = Options(highlightCode: true, autolinks: true, interactiveTasks: true)
            options.headingIDs = true
            options.footnotes = true
            options.emoji = true
            options.sanitizeHTML = true
            options.mermaid = true
            options.resolveImages = true
            options.extensions.math = true
            return options
        }

        /// Standalone export: like the preview, but tasks are disabled checkboxes and images keep
        /// the paths written in the document (the exported file sits next to it).
        public static var export: Options {
            var options = preview
            options.interactiveTasks = false
            options.resolveImages = false
            return options
        }
    }

    public static func html(for block: MarkdownBlock, id: String? = nil, options: Options = Options()) -> String {
        var renderer = Renderer(block: block)
        renderer.options = options
        renderer.render(block.markup)
        guard let id else { return renderer.output }
        // Raw HTML may contain several elements; wrap it so the block stays one node.
        if block.markup is HTMLBlock { return "<div data-block=\"\(id)\">\(renderer.output)</div>\n" }
        return tagged(renderer.output, id: id)
    }

    /// Complete document body, e.g. for export.
    public static func body(for blocks: [MarkdownBlock], options: Options = Options()) -> String {
        blocks.map { html(for: $0, options: options) }.joined()
    }

    static func tagged(_ html: String, id: String) -> String {
        // Insert the attribute after the first tag name; wrap anything that does not start with an element.
        guard html.first == "<", let second = html.dropFirst().first, second.isLetter,
              let nameEnd = html.dropFirst().firstIndex(where: { !$0.isLetter && !$0.isNumber }) else {
            return "<div data-block=\"\(id)\">\(html)</div>\n"
        }
        var result = html
        result.insert(contentsOf: " data-block=\"\(id)\"", at: nameEnd)
        return result
    }
}

struct Renderer {
    let block: MarkdownBlock
    var output = ""
    var options = HTMLRenderer.Options()
    var linkDepth = 0
    var taskIndex = 0
    /// UTF-16 units to skip at the start of the next text run (footnote definition marker).
    var skipTextPrefix = 0
    /// Paragraphs in tight lists render without `<p>`.
    var tightListDepth: [Bool] = []

    init(block: MarkdownBlock) {
        self.block = block
    }

    // Dispatch only. Every case body lives in its own non-inlined function: rendering recurses
    // once per nesting level, and one big switch made each level's stack frame so large that
    // a few nested lists overflowed a 512 KB background thread (F10, crash reports 2026-09-24).
    // swiftlint:disable:next cyclomatic_complexity
    mutating func render(_ node: Markup) {
        switch node {
        case let heading as Heading: renderHeading(heading)
        case let paragraph as Paragraph: renderParagraph(paragraph)
        case let quote as BlockQuote: renderQuote(quote)
        case let list as UnorderedList: renderUnorderedList(list)
        case let list as OrderedList: renderOrderedList(list)
        case let item as ListItem: renderListItem(item)
        case let code as CodeBlock: renderCodeBlock(code)
        case let html as HTMLBlock: renderHTML(html.rawHTML)
        case is ThematicBreak: output += "<hr />\n"
        case let table as Table: renderTable(table)
        case let text as Text: renderText(text.string)
        case is SoftBreak: output += "\n"
        case is LineBreak: output += "<br />\n"
        case let code as InlineCode: renderInlineCode(code)
        case let emphasis as Emphasis: renderWrapped(emphasis, open: "<em>", close: "</em>")
        case let strong as Strong: renderWrapped(strong, open: "<strong>", close: "</strong>")
        case let strike as Strikethrough: renderStrikethrough(strike)
        case let link as Link: renderLink(link)
        case let image as Image: renderImage(image)
        case let html as InlineHTML: renderHTML(html.rawHTML)
        default: renderChildren(node)
        }
    }

}

// MARK: Text, lists and tables

extension Renderer {
    // One case per extension kind reads best as a single switch.
    // swiftlint:disable:next cyclomatic_complexity
    mutating func renderText(_ raw: String) {
        var string = raw
        if skipTextPrefix > 0 {
            string = (raw as NSString).substring(from: min(skipTextPrefix, (raw as NSString).length))
            skipTextPrefix = 0
        }
        let anyExtension = options.autolinks || options.footnotes || options.emoji
            || options.extensions.highlight || options.extensions.superscript
        guard anyExtension, linkDepth == 0 else {
            output += escape(string)
            return
        }
        let text = string as NSString
        var cursor = 0
        for match in InlineExtensions.matches(in: string, settings: options.extensions, autolinks: options.autolinks) {
            let replacement: String
            switch match.kind {
            case .footnote(let label):
                guard options.footnotes else { continue }
                replacement = footnoteReference(label)
            case .autolink(let url):
                replacement = "<a href=\"\(escapeHref(url))\">\(escape(text.substring(with: match.range)))</a>"
            case .emoji(let emoji):
                guard options.emoji else { continue }
                replacement = emoji
            case .mark(let inner):
                replacement = "<mark>\(escape(inner))</mark>"
            case .superscript(let inner):
                replacement = "<sup>\(escape(inner))</sup>"
            case .math(let tex):
                guard let math = MathRenderer.shared.html(tex: tex, displayMode: false) else { continue }
                replacement = math
            }
            output += escape(text.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            output += replacement
            cursor = NSMaxRange(match.range)
        }
        output += escape(text.substring(from: cursor))
    }

    func footnoteReference(_ label: String) -> String {
        let escaped = escape(label)
        let title = options.footnoteTexts[label].map { " title=\"\(escape($0))\"" } ?? ""
        return "<sup class=\"footnote-ref\"><a href=\"#fn-\(escaped)\" id=\"fnref-\(escaped)\"\(title)>"
            + "\(escaped)</a></sup>"
    }

    /// Raw HTML through the sanitizer; `<img src>` resolves like Markdown images.
    func sanitized(_ html: String) -> String {
        guard options.resolveImages else { return HTMLSanitizer.sanitize(html) }
        let base = options.imageBase
        return HTMLSanitizer.sanitize(html) { ImageLinks.previewSource($0, base: base) }
    }

    mutating func renderChildren(_ node: Markup) {
        for child in node.children { render(child) }
    }

    mutating func renderList(_ list: Markup) {
        tightListDepth.append(isTight(list))
        renderChildren(list)
        tightListDepth.removeLast()
    }

    private mutating func renderListItem(_ item: ListItem) {
        output += "<li>"
        if let checkbox = item.checkbox {
            let checked = checkbox == .checked ? " checked=\"\"" : ""
            if options.interactiveTasks {
                output += "<input type=\"checkbox\" data-task=\"\(taskIndex)\"\(checked) /> "
                taskIndex += 1
            } else {
                output += "<input type=\"checkbox\" disabled=\"\"\(checked) /> "
            }
        }
        let tight = tightListDepth.last ?? false
        if !tight, item.childCount > 0 { output += "\n" }
        renderChildren(item)
        output += "</li>\n"
    }

    /// CommonMark: a list is loose if any items, or any two blocks inside an item,
    /// are separated by a blank line.
    private func isTight(_ list: Markup) -> Bool {
        let items = Array(list.children)
        for (index, item) in items.enumerated() {
            let children = Array(item.children)
            if index + 1 < items.count, let current = lastChildLine(of: item),
               let next = block.fragmentLines(of: items[index + 1]), next.lowerBound > current + 1 {
                return false
            }
            for pair in zip(children, children.dropFirst()) {
                if let upper = endLine(of: pair.0), let lower = block.fragmentLines(of: pair.1),
                   lower.lowerBound > upper + 1 {
                    return false
                }
            }
        }
        return true
    }

    /// End line of an item's last child: blank lines inside that child (e.g. a `>` line in a quote)
    /// belong to the item, but trailing blank lines after it do not.
    private func lastChildLine(of item: Markup) -> Int? {
        guard let last = item.children.reversed().first(where: { $0.range != nil }) else {
            return block.fragmentLines(of: item)?.lowerBound
        }
        return endLine(of: last)
    }

    /// cmark extends list ranges over trailing blank lines, so a list ends where its last item's content ends.
    private func endLine(of node: Markup) -> Int? {
        if node is UnorderedList || node is OrderedList || node is ListItem,
           let last = node.children.reversed().first(where: { $0.range != nil }) {
            return endLine(of: last)
        }
        return block.fragmentLines(of: node)?.upperBound
    }

    mutating func renderTable(_ table: Table) {
        output += "<table>\n<thead>\n<tr>\n"
        let alignments = table.columnAlignments
        for (column, cell) in table.head.cells.enumerated() {
            output += "<th\(alignAttribute(alignments, column))>"
            renderChildren(cell)
            output += "</th>\n"
        }
        output += "</tr>\n</thead>\n"
        let rows = Array(table.body.rows)
        if !rows.isEmpty {
            output += "<tbody>\n"
            for row in rows {
                output += "<tr>\n"
                for (column, cell) in row.cells.enumerated() {
                    output += "<td\(alignAttribute(alignments, column))>"
                    renderChildren(cell)
                    output += "</td>\n"
                }
                output += "</tr>\n"
            }
            output += "</tbody>\n"
        }
        output += "</table>\n"
    }

    private func alignAttribute(_ alignments: [Table.ColumnAlignment?], _ column: Int) -> String {
        guard column < alignments.count, let alignment = alignments[column] else { return "" }
        switch alignment {
        case .left: return " align=\"left\""
        case .center: return " align=\"center\""
        case .right: return " align=\"right\""
        }
    }
}
