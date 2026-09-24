import Foundation
import Markdown

/// A standalone export of a document: HTML with inline styles, a title and the heading outline.
public enum ExportDocument {
    /// Front matter `title:`, otherwise the first heading, otherwise `fallback` (the file name).
    public static func title(text: NSString, blocks: [MarkdownBlock], fallback: String) -> String {
        if let frontMatter = FrontMatter.detect(in: text) {
            for line in text.substring(with: frontMatter.contentRange).split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "title" else { continue }
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !value.isEmpty { return value }
            }
        }
        return DocumentOutline.items(in: blocks, text: text).first?.title ?? fallback
    }

    /// The rendered body without the front matter (YAML is metadata, not content).
    public static func body(blocks: [MarkdownBlock], text: NSString, options: HTMLRenderer.Options) -> String {
        PreviewRenderer.renderAll(blocks, text: text, options: options)
            .filter { !$0.id.hasPrefix("fm-") }
            .map(\.html)
            .joined()
    }

    /// A complete HTML5 page. Scripts are forbidden by the Content Security Policy, so an exported
    /// file stays inert wherever it is opened.
    public static func html(body: String, title: String, stylesheet: String, language: String = "en") -> String {
        """
        <!doctype html>
        <html lang="\(HTMLSanitizer.escape(language))">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; \
        img-src * data: file: 'self'; style-src 'unsafe-inline'; font-src data:">
        <meta name="generator" content="Hashline">
        <title>\(HTMLSanitizer.escape(title))</title>
        <style>
        \(stylesheet)
        </style>
        </head>
        <body>
        \(body)</body>
        </html>

        """
    }

    /// Whether any top-level block is a Mermaid diagram (they need a web view to render).
    public static func containsDiagrams(_ blocks: [MarkdownBlock]) -> Bool {
        blocks.contains { ($0.markup as? CodeBlock)?.language?.split(separator: " ").first == "mermaid" }
    }

    /// Parent index of each outline entry by heading level (nil = top level), for PDF bookmarks.
    /// A level-3 heading directly under a level-1 heading nests under it.
    public static func outlineParents(levels: [Int]) -> [Int?] {
        var stack: [(index: Int, level: Int)] = []
        return levels.enumerated().map { index, level in
            while let last = stack.last, last.level >= level { stack.removeLast() }
            let parent = stack.last?.index
            stack.append((index, level))
            return parent
        }
    }
}
