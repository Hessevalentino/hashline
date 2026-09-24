import Foundation
import Markdown

/// One function per node type (see `Renderer.render`): small stack frames on the recursive path.
extension Renderer {
    @inline(never)
    mutating func renderHeading(_ heading: Heading) {
        let anchor = options.headingIDs ? " id=\"\(escape(TableOfContents.slug(heading.plainText)))\"" : ""
        output += "<h\(heading.level)\(anchor)>"
        renderChildren(heading)
        output += "</h\(heading.level)>\n"
    }

    @inline(never)
    mutating func renderParagraph(_ paragraph: Paragraph) {
        if options.extensions.math, paragraph.parent is Document, let source = block.source(of: paragraph),
           let tex = MathSyntax.displayMath(inParagraphSource: source),
           let math = MathRenderer.shared.html(tex: tex, displayMode: true) {
            output += "<div class=\"math-display\">\(math)</div>\n"
        } else if let entries = options.tableOfContents, paragraph.parent is Document,
           TableOfContents.isPlaceholder(paragraph.plainText) {
            output += TableOfContents.html(for: entries)
        } else if options.footnotes, paragraph.parent is Document, let first = paragraph.child(at: 0) as? Text,
                  let definition = InlineExtensions.footnoteDefinition(in: first.string) {
            let label = escape(definition.label)
            output += "<div class=\"footnote\" id=\"fn-\(label)\"><sup>\(label)</sup> "
            skipTextPrefix = definition.prefixLength
            renderChildren(paragraph)
            output += " <a class=\"footnote-back\" href=\"#fnref-\(label)\">↩</a></div>\n"
        } else if tightListDepth.last == true && paragraph.parent is ListItem {
            renderChildren(paragraph)
            if paragraph.indexInParent < (paragraph.parent?.childCount ?? 1) - 1 { output += "\n" }
        } else {
            output += "<p>"
            renderChildren(paragraph)
            output += "</p>\n"
        }
    }

    @inline(never)
    mutating func renderQuote(_ quote: BlockQuote) {
        output += "<blockquote>\n"
        tightListDepth.append(false)
        renderChildren(quote)
        tightListDepth.removeLast()
        output += "</blockquote>\n"
    }

    @inline(never)
    mutating func renderUnorderedList(_ list: UnorderedList) {
        output += "<ul>\n"
        renderList(list)
        output += "</ul>\n"
    }

    @inline(never)
    mutating func renderOrderedList(_ list: OrderedList) {
        output += list.startIndex == 1 ? "<ol>\n" : "<ol start=\"\(list.startIndex)\">\n"
        renderList(list)
        output += "</ol>\n"
    }

    @inline(never)
    mutating func renderCodeBlock(_ code: CodeBlock) {
        let language = code.language?.split(separator: " ").first.map(String.init) ?? ""
        if options.extensions.math, language == "math",
           let math = MathRenderer.shared.html(tex: code.code, displayMode: true) {
            output += "<div class=\"math-display\">\(math)</div>\n"
        } else if options.mermaid, language == "mermaid", let svg = options.diagrams[code.code] {
            output += "<div class=\"mermaid-diagram\">\(svg)</div>\n"
        } else if options.mermaid, language == "mermaid" {
            // Rendered in the preview by Mermaid; the source stays visible until then.
            output += "<div class=\"mermaid-diagram\" data-mermaid=\"\(escape(code.code))\">"
                + "<pre><code>\(escape(code.code))</code></pre></div>\n"
        } else if options.highlightCode, !language.isEmpty,
           let highlighted = CodeHighlighter.shared.html(code: code.code, language: language) {
            output += "<pre><code class=\"hljs language-\(escape(language))\">" + highlighted + "</code></pre>\n"
        } else {
            output += language.isEmpty ? "<pre><code>" : "<pre><code class=\"language-\(escape(language))\">"
            output += escape(code.code)
            output += "</code></pre>\n"
        }
    }

    @inline(never)
    mutating func renderHTML(_ raw: String) {
        output += options.sanitizeHTML ? sanitized(raw) : raw
    }

    @inline(never)
    mutating func renderInlineCode(_ code: InlineCode) {
        output += "<code>\(escape(code.code))</code>"
    }

    @inline(never)
    mutating func renderWrapped(_ node: Markup, open: StaticString, close: StaticString) {
        output += open.description
        renderChildren(node)
        output += close.description
    }

    @inline(never)
    mutating func renderStrikethrough(_ strike: Strikethrough) {
        // `~x~` (single tilde) is subscript when that extension is on; `~~x~~` stays strikethrough.
        let isSubscript = options.extensions.subscriptText
            && (block.source(of: strike).map { !$0.hasPrefix("~~") } ?? false)
        output += isSubscript ? "<sub>" : "<del>"
        renderChildren(strike)
        output += isSubscript ? "</sub>" : "</del>"
    }

    @inline(never)
    mutating func renderLink(_ link: Link) {
        if options.footnotes && link.plainText.hasPrefix("^") && link.childCount == 1 {
            // `[^1]` whose one-word definition cmark took as a link reference definition.
            output += footnoteReference(String(link.plainText.dropFirst()))
            return
        }
        let destination = link.destination ?? ""
        // Sanitized output (preview, export, Quick Look) drops `javascript:` and other unsafe schemes;
        // the text stays, as a link without a target.
        let safe = !options.sanitizeHTML || HTMLSanitizer.isSafeURL(destination, allowImageData: false)
        output += safe ? "<a href=\"\(escapeHref(destination))\"" : "<a"
        if let title = link.title, !title.isEmpty { output += " title=\"\(escape(title))\"" }
        output += ">"
        linkDepth += 1
        renderChildren(link)
        linkDepth -= 1
        output += "</a>"
    }

    @inline(never)
    mutating func renderImage(_ image: Image) {
        var source = image.source ?? ""
        if options.sanitizeHTML, !HTMLSanitizer.isSafeURL(source, allowImageData: true) { source = "" }
        if options.resolveImages { source = ImageLinks.previewSource(source, base: options.imageBase) }
        output += "<img src=\"\(escapeHref(source))\" alt=\"\(escape(image.plainText))\""
        if let title = image.title, !title.isEmpty { output += " title=\"\(escape(title))\"" }
        if options.resolveImages { output += " loading=\"lazy\" decoding=\"async\"" }
        output += " />"
    }
}
