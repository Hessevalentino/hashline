import Testing
@testable import HashlineCore

struct LineEndingTests {
    @Test(arguments: [
        ("a\nb", LineEnding.lf),
        ("a\r\nb\nc", .crlf),
        ("a\rb", .cr),
        ("no break", .lf),
        ("", .lf),
        ("trailing\r", .cr),
        ("Příliš\r\nžluťoučký", .crlf)
    ])
    func detectsFirstLineBreak(text: String, expected: LineEnding) {
        #expect(LineEnding.detect(in: text) == expected)
    }
}
