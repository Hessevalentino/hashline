import Foundation
import Testing
@testable import HashlineCore

struct ExportTests {
    static let source = """
        ---
        title: "Zpráva <2026>"
        ---

        # Úvod

        - [x] hotovo
        - [ ] zbývá

        ![logo](assets/logo.png)

        ```mermaid
        graph TD; A-->B
        ```

        ## Detail
        """

    @Test func titleComesFromFrontMatterThenHeading() {
        let text = Self.source as NSString
        let blocks = BlockMap(text: Self.source).blocks
        #expect(ExportDocument.title(text: text, blocks: blocks, fallback: "x") == "Zpráva <2026>")
        let plain = "Text\n\n## Nadpis\n"
        #expect(ExportDocument.title(text: plain as NSString, blocks: BlockMap(text: plain).blocks,
                                     fallback: "soubor") == "Nadpis")
        #expect(ExportDocument.title(text: "" as NSString, blocks: [], fallback: "soubor") == "soubor")
    }

    @Test func exportBodyKeepsPathsDisablesTasksAndEmbedsDiagrams() {
        let text = Self.source as NSString
        var options = HTMLRenderer.Options.export
        options.diagrams = ["graph TD; A-->B\n": "<svg id=\"d\"></svg>"]
        let body = ExportDocument.body(blocks: BlockMap(text: Self.source).blocks, text: text, options: options)
        #expect(!body.contains("front-matter"), "Front matter is not content")
        #expect(body.contains("src=\"assets/logo.png\""))
        #expect(!body.contains("hashline-asset"))
        #expect(body.contains("disabled"))
        #expect(!body.contains("data-task"))
        #expect(body.contains("class=\"mermaid-diagram\"><svg id=\"d\"></svg></div>"))
        #expect(body.contains("id=\"uvod\"") || body.contains("id=\"úvod\""))
    }

    @Test func pageIsCompleteAndInert() {
        let page = ExportDocument.html(body: "<p>x</p>\n", title: "A & <B>", stylesheet: "body{}", language: "cs")
        #expect(page.hasPrefix("<!doctype html>"))
        #expect(page.contains("<html lang=\"cs\">"))
        #expect(page.contains("<title>A &amp; &lt;B&gt;</title>"))
        #expect(page.contains("default-src 'none'"))
        #expect(!page.contains("<script"))
        #expect(page.contains("<body>\n<p>x</p>\n</body>"))
    }

    @Test func outlineNestsByLevel() {
        #expect(ExportDocument.outlineParents(levels: [1, 2, 3, 2, 1, 3, 2]) == [nil, 0, 1, 0, nil, 4, 4])
        #expect(ExportDocument.outlineParents(levels: [2, 1]) == [nil, nil])
        #expect(ExportDocument.outlineParents(levels: []).isEmpty)
    }

    @Test func pandocArgumentsAreAnArray() {
        let arguments = Pandoc.exportArguments(format: .docx, outputPath: "/tmp/out file.docx",
                                               resourcePath: URL(fileURLWithPath: "/docs"))
        #expect(arguments == ["--from", "gfm+tex_math_dollars+footnotes+yaml_metadata_block", "--to", "docx",
                              "--standalone", "--output", "/tmp/out file.docx", "--resource-path", "/docs"])
        #expect(PandocFormat.latex.fileExtension == "tex")
        #expect(Pandoc.importArguments(fileExtension: "DOCX", inputPath: "in")
                == ["--from", "docx", "--to", "gfm-tex_math_gfm+tex_math_dollars", "--wrap", "none", "in"])
        #expect(Pandoc.importArguments(fileExtension: "pages", inputPath: "in") == nil)
    }

    /// The exported page parses as well-formed markup after tidying (no unclosed elements).
    @Test func exportedHTMLParses() throws {
        let text = Self.source as NSString
        let body = ExportDocument.body(blocks: BlockMap(text: Self.source).blocks, text: text, options: .export)
        let page = ExportDocument.html(body: body, title: "t", stylesheet: "")
        let document = try XMLDocument(xmlString: page, options: [.documentTidyHTML])
        #expect(try document.nodes(forXPath: "//h1").count == 1)
        #expect(try document.nodes(forXPath: "//li").count == 2)
    }
}
