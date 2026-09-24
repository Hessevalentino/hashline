import Foundation
import Testing
@testable import HashlineCore

/// CommonMark 0.29 spec examples (the version cmark-gfm in swift-markdown implements)
/// rendered through BlockMap + HTMLRenderer.
struct CommonMarkSpecTests {
    struct Example: Decodable, CustomTestStringConvertible, Sendable {
        let markdown: String
        let html: String
        let example: Int
        let section: String
        var testDescription: String { "\(example) \(section)" }
    }

    static let examples: [Example] = {
        guard let url = Bundle.module.url(forResource: "commonmark-spec-0.29", withExtension: "json",
                                          subdirectory: "Resources"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Example].self, from: data)) ?? []
    }()

    /// Constructs Hashline supports in F1. Raw HTML passes through unchanged (sanitised in F10).
    static let supportedSections: Set<String> = [
        "ATX headings", "Setext headings", "Thematic breaks", "Paragraphs", "Blank lines", "Block quotes",
        "List items", "Lists", "Emphasis and strong emphasis", "Code spans", "Fenced code blocks",
        "Indented code blocks", "Links", "Images", "Autolinks", "Hard line breaks", "Soft line breaks",
        "Textual content", "Backslash escapes", "Entity and numeric character references",
        "Link reference definitions", "Tabs", "Precedence", "Inlines", "HTML blocks", "Raw HTML",
    ]

    /// Known differences, each with a reason. Keep this list short and justified.
    static let knownFailures: [Int: String] = [
        622: "cmark-gfm (parser) still accepts HTML comments containing `--`; spec 0.29 does not",
        623: "cmark-gfm (parser) accepts `<!-->` as a comment; spec 0.29 does not",
    ]

    static func render(_ markdown: String) -> String {
        HTMLRenderer.body(for: BlockMap(text: markdown).blocks)
    }

    /// Whitespace between tags is not significant for comparison (as in the spec's own normaliser).
    static func normalize(_ html: String) -> String {
        html.replacingOccurrences(of: #">\s+<"#, with: "><", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func specIsBundled() {
        #expect(Self.examples.count == 649)
    }

    @Test(arguments: examples.filter { supportedSections.contains($0.section) && knownFailures[$0.example] == nil })
    func example(_ example: Example) {
        #expect(Self.normalize(Self.render(example.markdown)) == Self.normalize(example.html),
                "\(example.markdown.debugDescription)")
    }
}
