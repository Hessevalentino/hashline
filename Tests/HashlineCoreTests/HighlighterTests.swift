import Foundation
import Testing
@testable import HashlineCore

/// Snapshot tests: each span is written as «TOKEN|text» in document order (outer spans first).
struct HighlighterTests {
    static func snapshot(_ markdown: String) -> [String] {
        let text = markdown as NSString
        return BlockMap(text: markdown).blocks.flatMap { block in
            Highlighter.spans(for: block, in: text).map { "\($0.token.rawValue)|\(text.substring(with: $0.range))" }
        }
    }

    @Test func headings() {
        #expect(Self.snapshot("# One\n\nTwo\n===\n\n###### Six *em*\n") == [
            "H1|# One", "H1|Two\n===", "H6|###### Six *em*", "EMPH|*em*",
        ])
    }

    @Test func inlineMarkup() {
        #expect(Self.snapshot("a **b** _c_ ~~d~~ `e` [f](/g) ![h](/i) <https://j.k>\n") == [
            "STRONG|**b**", "EMPH|_c_", "STRIKE|~~d~~", "CODE|`e`", "LINK|[f](/g)", "IMAGE|![h](/i)",
            "AUTO_LINK_URL|<https://j.k>",
        ])
    }

    @Test func nestedInlineKeepsOuterFirst() {
        #expect(Self.snapshot("**bold *both***\n") == ["STRONG|**bold *both***", "EMPH|*both*"])
        #expect(Self.snapshot("***all***\n") == ["EMPH|***all***", "STRONG|**all**"])
    }

    @Test func listsAndTasks() {
        #expect(Self.snapshot("- a\n- [ ] b\n- [x] c\n\n3) d\n") == [
            "LIST_BULLET|-", "LIST_BULLET|- [ ]", "LIST_BULLET|- [x]", "LIST_ENUMERATOR|3)",
        ])
    }

    @Test func blocks() {
        #expect(Self.snapshot("> q **s**\n\n```swift\nlet a = 1\n```\n\n    code\n\n---\n\n<!-- c -->\n") == [
            "BLOCKQUOTE|> q **s**", "STRONG|**s**", "VERBATIM|```swift\nlet a = 1\n```", "VERBATIM|code",
            "HRULE|---", "COMMENT|<!-- c -->",
        ])
    }

    @Test func unicodeOffsets() {
        #expect(Self.snapshot("🙂 **ž** 𝒳 *a*\n") == ["STRONG|**ž**", "EMPH|*a*"])
    }

    @Test func paragraphAfterDefinitionIsNotShifted() {
        // cmark-gfm reports these inline positions one line early; BlockMap corrects them.
        #expect(Self.snapshot("[r]: /u\nText **b** [l][r]\n") == ["STRONG|**b**", "LINK|[l][r]"])
    }
}
