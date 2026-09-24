import Foundation
import Testing
@testable import HashlineCore

struct MathTests {
    static func inlineMath(_ text: String) -> [String] {
        InlineExtensions.matches(in: text, settings: InlineExtensionSettings(math: true)).compactMap {
            if case .math(let tex) = $0.kind { return tex }
            return nil
        }
    }

    @Test func inlineMathRules() {
        #expect(Self.inlineMath("Einstein $E = mc^2$ said") == ["E = mc^2"])
        #expect(Self.inlineMath("Costs $5 and $10 today") == [])
        #expect(Self.inlineMath("$ x $ has spaces") == [])
        #expect(Self.inlineMath("two $a$ and $b$") == ["a", "b"])
        #expect(Self.inlineMath("$$x$$ is not inline") == [])
        #expect(Self.inlineMath("escaped \\$x$ stays") == [])
    }

    @Test func displayMathParagraph() {
        #expect(MathSyntax.displayMath(inParagraphSource: "$$\n\\int x\\,dx\n$$") == "\\int x\\,dx")
        #expect(MathSyntax.displayMath(inParagraphSource: "$$x$$") == "x")
        #expect(MathSyntax.displayMath(inParagraphSource: "$$ only open") == nil)
    }

    @Test func katexRendersAndIsCached() throws {
        let html = try #require(MathRenderer.shared.html(tex: "\\frac{a}{b}", displayMode: false))
        #expect(html.contains("class=\"katex\""))
        #expect(html.contains("<math"), "MathML for VoiceOver")
        #expect(MathRenderer.shared.html(tex: "\\frac{a}{b}", displayMode: false) == html)
    }

    @Test func katexDoesNotTrustLinks() throws {
        let html = try #require(MathRenderer.shared.html(tex: "\\href{javascript:alert(1)}{x}", displayMode: false))
        // The TeX source stays in <annotation> as text; what must not appear is a link.
        #expect(!html.contains("href=\"javascript"))
        #expect(!html.contains("<a "))
    }

    @Test func invalidTeXRendersAsError() throws {
        let html = try #require(MathRenderer.shared.html(tex: "\\frac{", displayMode: true))
        #expect(html.contains("katex-error") || html.contains("color"))
    }

    @Test func previewOutput() {
        let markdown = "$$\nx^2\n$$\n\n```math\ny\n```\n\n```mermaid\ngraph TD; A-->B\n```\n\nText $z$.\n"
        let html = HTMLRenderer.body(for: BlockMap(text: markdown).blocks, options: {
            var options = HTMLRenderer.Options.preview
            options.highlightCode = false
            return options
        }())
        #expect(html.components(separatedBy: "<div class=\"math-display\">").count == 3)
        #expect(html.contains("<div class=\"mermaid-diagram\" data-mermaid=\"graph TD; A--&gt;B\n\">"))
        #expect(html.contains("class=\"katex\""))
    }
}
