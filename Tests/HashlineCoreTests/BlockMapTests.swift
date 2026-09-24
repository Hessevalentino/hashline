import Foundation
import Testing
@testable import HashlineCore

struct BlockMapTests {
    /// Deterministic generator so failures reproduce.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    static let seedDocument = """
        # Title

        Paragraph with **bold**, *em*, `code` and [link][ref].
        Setext candidate
        ---

        - item one
        - item two
          - nested

        1. first
        2. second

        > quote
        > more

        ```swift
        let x = 1
        ```

            indented code

        <div>html</div>

        | a | b |
        |---|---|
        | 1 | 2 |

        [ref]: https://example.com
        Příliš žluťoučký kůň 🙂 end.
        """

    /// Snippets that change block structure: fences, list markers, setext underlines, definitions.
    static let snippets = ["\n", "\n\n", "```", "~~~", "# ", "- ", "1. ", "> ", "---", "===", "    ",
                           "**", "*", "`", "[x]: /u", "[ref]", "|", "<div>", "a", "ž", "🙂", "\r\n", ""]

    static func snapshot(_ map: BlockMap) -> [String] {
        map.blocks.map { "\($0.range) \(HTMLRenderer.html(for: $0))" }
    }

    @Test(arguments: [1, 2, 3, 4, 5])
    func incrementalEditsMatchFullParse(seed: UInt64) {
        var generator = SeededGenerator(state: seed)
        let text = NSMutableString(string: Self.seedDocument)
        let map = BlockMap(text: text as String)

        for step in 0..<400 {
            let location = Int.random(in: 0...text.length, using: &generator)
            var length = min(Int.random(in: 0...4, using: &generator), text.length - location)
            // Never split a surrogate pair or CRLF: edits come from a text view, which does not either.
            var range = text.rangeOfComposedCharacterSequences(for: NSRange(location: location, length: length))
            if range.location > text.length { range = NSRange(location: text.length, length: 0) }
            length = range.length
            let insertion = Self.snippets.randomElement(using: &generator) ?? ""
            let replaced = text.substring(with: range)
            text.replaceCharacters(in: range, with: insertion)
            let edited = NSRange(location: range.location, length: (insertion as NSString).length)
            map.applyEdit(editedRange: edited, delta: edited.length - length, replacedText: replaced, in: text)
            map.validateDefinitions(in: text)  // as the debounced preview update does

            let expected = Self.snapshot(BlockMap(text: text as String))
            let actual = Self.snapshot(map)
            #expect(actual == expected, """
                seed \(seed) step \(step): replaced \(replaced.debugDescription) \
                with \(insertion.debugDescription) at \(range.location)
                """)
            if actual != expected {
                let index = zip(actual, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
                    ?? min(actual.count, expected.count)
                print("DIFF count \(actual.count) vs \(expected.count) at \(index)")
                print("ACTUAL  ", index < actual.count ? actual[index] : "-")
                print("EXPECTED", index < expected.count ? expected[index] : "-")
                return
            }
        }
    }

    @Test func offsetsAreUTF16() {
        let map = BlockMap(text: "🙂 *a*\n\n# Příliš\n")
        #expect(map.blocks.map(\.range) == [NSRange(location: 0, length: 6), NSRange(location: 8, length: 8)])
    }
}
