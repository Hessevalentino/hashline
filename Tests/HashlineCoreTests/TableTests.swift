import Foundation
import Testing
@testable import HashlineCore

/// `‸` marks the caret, `«…»` the selection (`|` is table content here).
struct TableTests {
    @Test func formatsAndKeepsAlignment() {
        #expect(Marked.apply("|a‸|b|\n|:-|-:|\n|long cell|1|") { TableCommand.format(in: $0, selection: $1) }
                == "| a‸         |   b |\n|:----------|----:|\n| long cell |   1 |")
    }

    @Test func tabNavigation() {
        let move = { (input: String, back: Bool) in
            Marked.apply(input) { TableCommand.moveCell(in: $0, selection: $1, backwards: back) }
        }
        #expect(move("| a‸ | b |\n|---|---|\n| 1 | 2 |", false) == "| a   | «b»   |\n|-----|-----|\n| 1   | 2   |")
        #expect(move("| a | b‸ |\n|---|---|\n| 1 | 2 |", false) == "| a   | b   |\n|-----|-----|\n| «1»   | 2   |")
        #expect(move("| a | b |\n|---|---|\n| 1 | 2‸ |", false)
                == "| a   | b   |\n|-----|-----|\n| 1   | 2   |\n| ‸    |     |")
        #expect(move("| a | b |\n|---|---|\n| 1‸ | 2 |", true) == "| a   | «b»   |\n|-----|-----|\n| 1   | 2   |")
        #expect(move("| a‸ | b |\n|---|---|\n| 1 | 2 |", true) == "unchanged")
    }

    @Test func rowsAndColumns() {
        let text = "| a | b |\n|---|---|\n| 1‸ | 2 |"
        #expect(Marked.apply(text) { TableCommand.insertRow(in: $0, selection: $1, below: true) }
                == "| a   | b   |\n|-----|-----|\n| 1   | 2   |\n| ‸    |     |")
        #expect(Marked.apply(text) { TableCommand.deleteRow(in: $0, selection: $1) }
                == "| ‸a   | b   |\n|-----|-----|")
        #expect(Marked.apply(text) { TableCommand.insertColumn(in: $0, selection: $1, right: true) }
                == "| a   |     | b   |\n|-----|-----|-----|\n| 1   | ‸    | 2   |")
        #expect(Marked.apply(text) { TableCommand.deleteColumn(in: $0, selection: $1) }
                == "| b   |\n|-----|\n| ‸2   |")
        #expect(Marked.apply(text) { TableCommand.align(.center, in: $0, selection: $1) }
                == "|  a  | b   |\n|:---:|-----|\n|  1‸  | 2   |")
    }

    @Test func tableAfterParagraph() {
        let input = "Intro\n\n| x | y |\n|--|--|\n| 1‸ |2|\n\nAfter"
        #expect(Marked.apply(input) { TableCommand.format(in: $0, selection: $1) }
                == "Intro\n\n| x   | y   |\n|-----|-----|\n| 1‸   | 2   |\n\nAfter")
    }

    @Test func notATable() {
        #expect(Marked.apply("a ‸| b") { TableCommand.format(in: $0, selection: $1) } == "unchanged")
        #expect(MarkdownTable.cells(of: "| `a|b` | c\\|d |") == ["`a|b`", "c\\|d"])
    }
}
