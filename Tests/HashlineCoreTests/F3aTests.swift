import Foundation
import Testing
@testable import HashlineCore

struct F3aTests {
    static func preview(_ markdown: String, extensions: InlineExtensionSettings = InlineExtensionSettings()) -> String {
        var options = HTMLRenderer.Options.preview
        options.highlightCode = false
        options.extensions = extensions
        let update = PreviewRenderer().update(for: BlockMap(text: markdown).blocks, text: markdown as NSString,
                                              options: options)
        // Drop data-block ids for readable expectations.
        return update.html.replacingOccurrences(of: #" data-block="[^"]*""#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func frontMatter() throws {
        let text = "---\ntitle: Kniha\ntags: [a]\n---\n\n# Obsah\n" as NSString
        let frontMatter = try #require(FrontMatter.detect(in: text))
        #expect(text.substring(with: frontMatter.contentRange) == "title: Kniha\ntags: [a]\n")
        #expect(FrontMatter.detect(in: "---\nno closing\n") == nil)
        #expect(FrontMatter.detect(in: "text\n---\n") == nil)
        let html = Self.preview(text as String)
        #expect(html.hasPrefix("<details class=\"front-matter\"><summary>Front matter</summary>"))
        #expect(html.contains("<h1 id=\"obsah\">Obsah</h1>"))
        #expect(!html.contains("<hr"), "front matter must not render as a rule and heading")
    }

    @Test func tableOfContents() {
        let html = Self.preview("[toc]\n\n# Úvod\n\n## Detail věci\n\n# Závěr\n")
        #expect(html.hasPrefix("""
            <nav class="toc">
            <ul>
            <li><a href="#úvod">Úvod</a>
            <ul>
            <li><a href="#detail-věci">Detail věci</a></li>
            </ul>
            </li>
            <li><a href="#závěr">Závěr</a></li>
            </ul>
            </nav>
            """))
    }

    @Test func tocUpdatesWhenHeadingsChange() {
        let renderer = PreviewRenderer()
        var options = HTMLRenderer.Options.preview
        options.highlightCode = false
        let first = BlockMap(text: "[toc]\n\n# A\n")
        _ = renderer.update(for: first.blocks, options: options)
        let text = NSMutableString(string: "[toc]\n\n# A\n")
        text.append("\n# B\n")
        first.applyEdit(editedRange: NSRange(location: 11, length: 5), delta: 5, replacedText: "", in: text)
        let update = renderer.update(for: first.blocks, options: options)
        #expect(update.html.contains("<a href=\"#b\">B</a>"), "the [toc] entry is re-rendered")
    }

    @Test func footnotes() {
        let html = Self.preview("Text[^1] and more.\n\n[^1]: The note text.\n")
        #expect(html.contains(
            "<sup class=\"footnote-ref\"><a href=\"#fn-1\" id=\"fnref-1\" title=\"The note text.\">1</a></sup>"))
        #expect(html.contains("<div class=\"footnote\" id=\"fn-1\"><sup>1</sup> The note text. "
            + "<a class=\"footnote-back\" href=\"#fnref-1\">↩</a></div>"))
    }

    @Test func emojiAndExtensions() {
        #expect(Self.preview("Hi :smile: :notanemoji:") == "<p>Hi 😄 :notanemoji:</p>")
        #expect(Self.preview("==x== ^2^ ~sub~ ~~del~~") == "<p>==x== ^2^ <del>sub</del> <del>del</del></p>")
        let all = InlineExtensionSettings(highlight: true, superscript: true, subscriptText: true)
        #expect(Self.preview("==x== H^2^O ~sub~ ~~del~~", extensions: all)
                == "<p><mark>x</mark> H<sup>2</sup>O <sub>sub</sub> <del>del</del></p>")
        #expect(Self.preview("`:smile: ==x==`", extensions: all) == "<p><code>:smile: ==x==</code></p>")
    }

    @Test func emojiCompletions() {
        let names = Emoji.completions(for: "smi").map(\.name)
        #expect(names.first == "smile")
        #expect(names.contains("smiley"))
    }

    @Test(arguments: [
        ("<script>alert(1)</script>", "&lt;script&gt;alert(1)&lt;/script&gt;"),
        ("<img src=x onerror=alert(1)>", "<img src=\"x\">"),
        ("<img src=\"javascript:alert(1)\">", "<img>"),
        ("<a href=\"java\nscript:alert(1)\">x</a>", "<a>x</a>"),
        ("<a href=\"https://x.cz\" onclick=\"y()\">x</a>", "<a href=\"https://x.cz\">x</a>"),
        ("<img src=\"data:image/svg+xml;base64,AAA\">", "<img>"),
        ("<img src=\"a.png\" width=\"200\" style=\"zoom: 50%; background: url(x)\">",
         "<img src=\"a.png\" width=\"200\" style=\"zoom: 50%\">"),
        ("<kbd>⌘</kbd><br><details open><summary>S</summary>t</details>",
         "<kbd>⌘</kbd><br><details open=\"\"><summary>S</summary>t</details>"),
        ("<iframe src=\"https://x\"></iframe>", "&lt;iframe src=&quot;https://x&quot;&gt;&lt;/iframe&gt;"),
        ("<!-- hidden -->visible", "visible"),
        ("<svg onload=alert(1)>", "&lt;svg onload=alert(1)&gt;"),
    ])
    func sanitizer(html: String, expected: String) {
        #expect(HTMLSanitizer.sanitize(html) == expected)
    }

    @Test func slug() {
        #expect(TableOfContents.slug("Příliš žluťoučký kůň!") == "příliš-žluťoučký-kůň")
        #expect(TableOfContents.slug("C++ & Swift 6") == "c--swift-6")
    }
}
