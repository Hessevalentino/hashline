import Foundation
import Testing
@testable import HashlineCore

struct CodeHighlighterTests {
    @Test func tokensUseUTF16Offsets() throws {
        let code = "let s = \"🙂\" // c\n"
        let tokens = try #require(CodeHighlighter.shared.tokens(code: code, language: "swift"))
        let text = code as NSString
        let described = tokens.map { "\($0.scope)|\(text.substring(with: $0.range))" }
        #expect(described == ["keyword|let", "operator|=", "string|\"🙂\"", "comment|// c"])
    }

    @Test func aliasesAndUnknownLanguages() {
        #expect(CodeHighlighter.shared.supports("js"))
        #expect(CodeHighlighter.shared.supports("sh"))
        #expect(!CodeHighlighter.shared.supports("unknownlang"))
        #expect(CodeHighlighter.shared.tokens(code: "x", language: "unknownlang") == nil)
    }

    @Test func htmlIsEscaped() throws {
        let html = try #require(CodeHighlighter.shared.html(code: "a < b && \"<script>\"", language: "javascript"))
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test func fencedCodeRange() throws {
        let markdown = "Text\n\n```python\nprint(1)\n```\n" as NSString
        let block = try #require(BlockMap(text: markdown as String).blocks.last)
        let fenced = try #require(block.fencedCode(in: markdown))
        #expect(fenced.language == "python")
        #expect(markdown.substring(with: fenced.range) == "print(1)\n")
    }

    @Test func previewHighlightsButSpecOutputDoesNot() throws {
        let block = try #require(BlockMap(text: "```js\nlet a = 1\n```\n").blocks.first)
        #expect(HTMLRenderer.html(for: block) == "<pre><code class=\"language-js\">let a = 1\n</code></pre>\n")
        #expect(HTMLRenderer.html(for: block, options: .preview).contains("hljs-keyword"))
    }
}
