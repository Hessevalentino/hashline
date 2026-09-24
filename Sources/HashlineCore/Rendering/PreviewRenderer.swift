import Foundation
import Markdown

/// Minimal patch for the preview DOM. An edit replaces one contiguous run of blocks, so the patch
/// is: remove `removed`, then insert `html` after the block `anchor` (or at the top when nil).
public struct PreviewUpdate: Sendable, Equatable {
    public let anchor: String?
    public let removed: [String]
    public let html: String
    public let insertedCount: Int

    public var isEmpty: Bool { removed.isEmpty && insertedCount == 0 }
}

/// Tracks what the preview shows, so an edit re-renders only the changed run of blocks.
/// Document-level content (front matter, `[toc]`) is folded into entry ids: when it changes,
/// the affected entries get new ids and are re-rendered.
public final class PreviewRenderer {
    private var shown: [String] = []
    private var lastExtensions: InlineExtensionSettings?
    private var lastImageBase: URL?

    public init() {}

    private struct Entry {
        let id: String
        let render: () -> String
    }

    public func update(for blocks: [MarkdownBlock], text: NSString? = nil,
                       options base: HTMLRenderer.Options = .preview) -> PreviewUpdate {
        var options = base
        if options.resolveImages, options.imageBase == nil {
            options.imageBase = ImageLinks.base(documentURL: nil, text: text)
        }
        let entries = self.entries(for: blocks, text: text, options: &options)
        let imageBaseChanged = lastImageBase != options.imageBase && !shown.isEmpty
        lastImageBase = options.imageBase
        if imageBaseChanged || (lastExtensions.map { $0 != options.extensions } ?? false) {
            // Extension settings changed: every block may render differently.
            let removed = shown
            shown = []
            self.lastExtensions = options.extensions
            let update = diff(entries)
            return PreviewUpdate(anchor: nil, removed: removed, html: update.html, insertedCount: update.insertedCount)
        }
        lastExtensions = options.extensions
        return diff(entries)
    }

    private func diff(_ entries: [Entry]) -> PreviewUpdate {
        let order = entries.map(\.id)
        var prefix = 0
        let limit = min(order.count, shown.count)
        while prefix < limit, order[prefix] == shown[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < limit - prefix, order[order.count - 1 - suffix] == shown[shown.count - 1 - suffix] {
            suffix += 1
        }
        let removed = Array(shown[prefix..<(shown.count - suffix)])
        let insertedRange = prefix..<(order.count - suffix)
        let html = insertedRange.map { entries[$0].render() }.joined()
        shown = order
        return PreviewUpdate(anchor: prefix > 0 ? order[prefix - 1] : nil, removed: removed, html: html,
                             insertedCount: insertedRange.count)
    }

    private func entries(for blocks: [MarkdownBlock], text: NSString?,
                         options: inout HTMLRenderer.Options) -> [Entry] {
        var entries: [Entry] = []
        var remaining = blocks[...]

        if let text, let frontMatter = FrontMatter.detect(in: text) {
            let yaml = text.substring(with: frontMatter.contentRange)
            let highlighted = options.highlightCode ? CodeHighlighter.shared.html(code: yaml, language: "yaml") : nil
            let code = highlighted ?? HTMLSanitizer.escape(yaml)
            let id = "fm-\(yaml.hashValue)"
            let summary = HTMLSanitizer.escape(options.frontMatterLabel)
            entries.append(Entry(id: id) {
                "<details class=\"front-matter\" data-block=\"\(id)\"><summary>\(summary)</summary>"
                    + "<pre><code class=\"hljs language-yaml\">\(code)</code></pre></details>\n"
            })
            remaining = remaining.drop { $0.range.location < NSMaxRange(frontMatter.range) }
        }

        // Document-level data, collected only when the document uses it. Runs after every typing
        // pause over all blocks, so only paragraphs whose text starts with `[` are inspected.
        var hasTOC = false
        var footnotes: [String: String] = [:]
        for block in remaining {
            guard let paragraph = block.markup as? Paragraph,
                  (paragraph.child(at: 0) as? Text)?.string.hasPrefix("[") == true else { continue }
            let plain = paragraph.plainText
            if TableOfContents.isPlaceholder(plain) {
                hasTOC = true
            } else if options.footnotes, let definition = InlineExtensions.footnoteDefinition(in: plain) {
                footnotes[definition.label] = (plain as NSString).substring(from: definition.prefixLength)
            }
        }
        var headings: [TableOfContents.Entry] = []
        if hasTOC {
            for block in remaining {
                guard let heading = block.markup as? Heading else { continue }
                let title = heading.plainText
                headings.append(TableOfContents.Entry(level: heading.level, title: title,
                                                      slug: TableOfContents.slug(title)))
            }
            options.tableOfContents = headings
        }
        options.footnoteTexts = footnotes
        let tocSignature = hasTOC
            ? String(headings.map { "\($0.level)\($0.title)" }.joined(separator: "|").hashValue)
            : ""

        let renderOptions = options
        for block in remaining {
            var id = block.id
            if hasTOC, let paragraph = block.markup as? Paragraph, TableOfContents.isPlaceholder(paragraph.plainText) {
                id += "-toc\(tocSignature)"
            }
            let finalID = id
            entries.append(Entry(id: finalID) { HTMLRenderer.html(for: block, id: finalID, options: renderOptions) })
        }
        return entries
    }

    /// One rendered preview entry.
    public struct RenderedEntry: Sendable {
        public let id: String
        public let html: String
    }

    /// Renders all entries without touching the renderer's state, so it can run off the main thread
    /// (the Markdown tree is immutable). Pair with `markShown(_:extensions:)`.
    public static func renderAll(_ blocks: [MarkdownBlock], text: NSString?,
                                 options base: HTMLRenderer.Options) -> [RenderedEntry] {
        var options = base
        return PreviewRenderer().entries(for: blocks, text: text, options: &options)
            .map { RenderedEntry(id: $0.id, html: $0.render()) }
    }

    /// Records that the DOM now shows exactly `ids` (after inserting a background render).
    public func markShown(_ ids: [String], extensions: InlineExtensionSettings) {
        shown = ids
        lastExtensions = extensions
    }

    /// Forget what is shown, e.g. after the page was reloaded.
    public func reset() {
        shown = []
        lastExtensions = nil
    }
}
