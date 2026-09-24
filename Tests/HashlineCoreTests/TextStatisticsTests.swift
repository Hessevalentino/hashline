import Foundation
import Testing
@testable import HashlineCore

struct TextStatisticsTests {
    @Test(arguments: [
        ("", 0, 0, 0),
        ("one", 1, 3, 1),
        ("Příliš žluťoučký kůň", 3, 20, 1),
        ("# Title\n\n- item one\n- item two", 5, 30, 4),
        ("can't stop", 2, 10, 1),
        ("a\r\nb\rc", 3, 6, 3),
        ("emoji 🙂 here", 2, 12, 1),
    ])
    func counts(text: String, words: Int, characters: Int, lines: Int) {
        let statistics = TextStatistics.of(text as NSString)
        #expect(statistics.words == words)
        #expect(statistics.characters == characters)
        #expect(statistics.lines == lines)
    }

    @Test func readingTime() {
        let text = String(repeating: "slovo ", count: 1_000) as NSString
        #expect(TextStatistics.of(text).readingMinutes == 5)
    }
}
