import Foundation
import Testing
@testable import HashlineCore

/// GFM spec "Autolinks (extension)" examples, as rendered HTML.
struct AutolinkTests {
    static func render(_ markdown: String) -> String {
        HTMLRenderer.body(for: BlockMap(text: markdown).blocks, options: HTMLRenderer.Options(autolinks: true))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test(arguments: [
        ("www.commonmark.org", "<p><a href=\"http://www.commonmark.org\">www.commonmark.org</a></p>"),
        ("Visit www.commonmark.org/help for more information.",
         "<p>Visit <a href=\"http://www.commonmark.org/help\">www.commonmark.org/help</a> for more information.</p>"),
        ("Visit www.commonmark.org.", "<p>Visit <a href=\"http://www.commonmark.org\">www.commonmark.org</a>.</p>"),
        ("Visit www.commonmark.org/a.b.",
         "<p>Visit <a href=\"http://www.commonmark.org/a.b\">www.commonmark.org/a.b</a>.</p>"),
        ("www.google.com/search?q=Markup+(business)",
         "<p><a href=\"http://www.google.com/search?q=Markup+(business)\">"
            + "www.google.com/search?q=Markup+(business)</a></p>"),
        ("(www.google.com/search?q=Markup+(business))",
         "<p>(<a href=\"http://www.google.com/search?q=Markup+(business)\">"
            + "www.google.com/search?q=Markup+(business)</a>)</p>"),
        ("www.google.com/search?q=commonmark&hl;",
         "<p><a href=\"http://www.google.com/search?q=commonmark\">www.google.com/search?q=commonmark</a>"
            + "&amp;hl;</p>"),
        ("www.commonmark.org/he<lp", "<p><a href=\"http://www.commonmark.org/he\">www.commonmark.org/he</a>&lt;lp</p>"),
        ("http://commonmark.org", "<p><a href=\"http://commonmark.org\">http://commonmark.org</a></p>"),
        ("foo@bar.baz", "<p><a href=\"mailto:foo@bar.baz\">foo@bar.baz</a></p>"),
        ("a.b-c_d@a.b.", "<p><a href=\"mailto:a.b-c_d@a.b\">a.b-c_d@a.b</a>.</p>"),
        ("a.b-c_d@a.b-", "<p>a.b-c_d@a.b-</p>"),
        ("[link](http://x.cz) and http://y.cz",
         "<p><a href=\"http://x.cz\">link</a> and <a href=\"http://y.cz\">http://y.cz</a></p>"),
        ("`www.code.org`", "<p><code>www.code.org</code></p>"),
    ])
    func autolink(markdown: String, expected: String) {
        #expect(Self.render(markdown) == expected)
    }
}

struct TaskAndLinkTests {
    @Test func toggleTask() throws {
        let text = "- [ ] one\n- [x] two\n  - [ ] nested\n" as NSString
        let block = try #require(BlockMap(text: text as String).blocks.first)
        let toggled = { (index: Int) in block.toggleTask(at: index, in: text)?.applied(to: text as String) }
        #expect(toggled(0) == "- [x] one\n- [x] two\n  - [ ] nested\n")
        #expect(toggled(1) == "- [ ] one\n- [ ] two\n  - [ ] nested\n")
        #expect(toggled(2) == "- [ ] one\n- [x] two\n  - [x] nested\n")
        #expect(block.toggleTask(at: 3, in: text) == nil)
    }

    @Test func interactiveTasksInPreview() throws {
        let block = try #require(BlockMap(text: "- [ ] a\n- [x] b\n").blocks.first)
        let html = HTMLRenderer.html(for: block, options: .preview)
        #expect(html.contains("<input type=\"checkbox\" data-task=\"0\" />"))
        #expect(html.contains("<input type=\"checkbox\" data-task=\"1\" checked=\"\" />"))
        #expect(!html.contains("disabled"))
    }

    @Test func linkUnderPointer() throws {
        let text = "See [docs](https://a.cz) or www.b.cz now." as NSString
        let block = try #require(BlockMap(text: text as String).blocks.first)
        #expect(block.link(at: 6, in: text) == "https://a.cz")
        #expect(block.link(at: 30, in: text) == "http://www.b.cz")
        #expect(block.link(at: 1, in: text) == nil)
    }

    @Test func autolinkIsHighlighted() {
        #expect(HighlighterTests.snapshot("see www.hashline.cz now\n") == ["AUTO_LINK_URL|www.hashline.cz"])
    }
}
