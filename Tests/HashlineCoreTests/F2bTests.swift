import Foundation
import Testing
@testable import HashlineCore

struct InsertCommandTests {
    static func apply(_ marked: String, _ command: (NSString, NSRange) -> [TextEdit]) -> String {
        let (text, selection) = Marked.parse(marked)
        var result = text as String
        var last = selection
        for edit in command(text, selection) {
            result = edit.applied(to: result)
            last = edit.selection
        }
        return Marked.render(result, last)
    }

    @Test func footnote() {
        #expect(Self.apply("Text| more.") { InsertCommand.footnote(in: $0, selection: $1) }
                == "Text[^1] more.\n\n[^1]: |")
        #expect(Self.apply("A[^1] b|\n\n[^1]: one\n") { InsertCommand.footnote(in: $0, selection: $1) }
                == "A[^1] b[^2]\n\n[^1]: one\n[^2]: |")
        #expect(Self.apply("|") { InsertCommand.footnote(in: $0, selection: $1) } == "[^1]\n\n[^1]: |")
    }

    @Test func blocks() {
        #expect(Marked.apply("|") { InsertCommand.mathBlock(in: $0, selection: $1) } == "$$\n|\n$$")
        #expect(Marked.apply("Intro|") { InsertCommand.tableOfContents(in: $0, selection: $1) } == "Intro\n\n[toc]|")
        #expect(Marked.apply("# Doc|") { InsertCommand.frontMatter(in: $0, selection: $1) }
                == "---\ntitle: |\n---\n\n# Doc")
        #expect(Marked.apply("---\ntitle: x\n---\n# Doc|") { InsertCommand.frontMatter(in: $0, selection: $1) }
                == "---\n|title: x\n---\n# Doc")
    }

    @Test func pastedURLOverSelectionMakesLink() {
        let paste = { (url: String) in { InsertCommand.linkFromPastedURL(url, in: $0, selection: $1) } }
        #expect(Marked.apply("see «docs» now", paste("https://example.com")) == "see [docs](https://example.com)| now")
        #expect(Marked.apply("see |", paste("https://example.com")) == "unchanged")
        #expect(Marked.apply("«x»", paste("not a url")) == "unchanged")
        #expect(Marked.apply("«x»", paste("javascript:alert(1)")) == "unchanged")
    }
}

struct HTMLToMarkdownTests {
    @Test(arguments: [
        ("<p>Hello <b>bold</b> and <i>it</i></p>", "Hello **bold** and *it*"),
        ("<h2>Title</h2><p>Text</p>", "## Title\n\nText"),
        ("<ul><li>a</li><li>b<ul><li>c</li></ul></li></ul>", "- a\n- b\n  - c"),
        ("<ol><li>one</li><li>two</li></ol>", "1. one\n2. two"),
        ("<p><a href=\"https://x.cz\">odkaz</a></p>", "[odkaz](https://x.cz)"),
        ("<p><a href=\"javascript:alert(1)\">x</a></p>", "x"),
        ("<blockquote><p>quote</p></blockquote>", "> quote"),
        ("<pre><code class=\"language-swift\">let a = 1</code></pre>", "```swift\nlet a = 1\n```"),
        ("<p>a<br>b</p>", "a  \nb"),
        ("<p>2 * 3 = 6</p>", "2 \\* 3 = 6"),
        ("<p><u>under</u> <del>gone</del> <code>x</code></p>", "<u>under</u> ~~gone~~ `x`"),
        ("<script>alert(1)</script><p>safe</p>", "safe"),
        ("<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>",
         "| A | B |\n|---|---|\n| 1 | 2 |"),
        ("<p>Příliš   žluťoučký\n kůň</p>", "Příliš žluťoučký kůň"),
    ])
    func convert(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html) == expected)
    }
}

struct PlainTextRendererTests {
    @Test func stripsMarkup() {
        let markdown = "# Title\n\nSome **bold** and [link](/x).\n\n- a\n- [x] b\n\n1. one\n\n```\ncode\n```\n"
        #expect(PlainTextRenderer.plainText(from: markdown)
                == "Title\n\nSome bold and link.\n\n• a\n• ☑ b\n\n1. one\n\ncode")
    }

    @Test func htmlForCopy() {
        #expect(PlainTextRenderer.html(from: "**b**") == "<p><strong>b</strong></p>\n")
    }
}
