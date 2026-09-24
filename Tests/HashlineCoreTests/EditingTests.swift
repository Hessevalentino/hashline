import Foundation
import Testing
@testable import HashlineCore

/// Cases are written as text with `|` for the caret or `«…»` for the selection.
enum Marked {
    /// `‸` marks the caret where `|` is content (tables); otherwise `|` does.
    static func parse(_ marked: String) -> (NSString, NSRange) {
        var text = marked
        if let caret = text.range(of: marked.contains("‸") ? "‸" : "|") {
            let location = (String(text[..<caret.lowerBound]) as NSString).length
            text.removeSubrange(caret)
            return (text as NSString, NSRange(location: location, length: 0))
        }
        guard let open = text.range(of: "«") else { return (text as NSString, NSRange(location: 0, length: 0)) }
        let location = (String(text[..<open.lowerBound]) as NSString).length
        text.removeSubrange(open)
        guard let close = text.range(of: "»") else { return (text as NSString, NSRange(location: location, length: 0)) }
        let end = (String(text[..<close.lowerBound]) as NSString).length
        text.removeSubrange(close)
        return (text as NSString, NSRange(location: location, length: end - location))
    }

    static func render(_ text: String, _ selection: NSRange, caret: String = "|") -> String {
        let string = text as NSString
        if selection.length == 0 { return string.replacingCharacters(in: selection, with: caret) }
        let withClose = string.replacingCharacters(in: NSRange(location: NSMaxRange(selection), length: 0), with: "»")
        let start = NSRange(location: selection.location, length: 0)
        return (withClose as NSString).replacingCharacters(in: start, with: "«")
    }

    static func apply(_ marked: String, _ command: (NSString, NSRange) -> TextEdit?) -> String {
        let (text, selection) = parse(marked)
        guard let edit = command(text, selection) else { return "unchanged" }
        return render(edit.applied(to: text as String), edit.selection, caret: marked.contains("‸") ? "‸" : "|")
    }
}

struct InlineStyleTests {
    @Test(arguments: [
        ("a «word» b", InlineStyle.bold, "a **«word»** b"),
        ("a **«word»** b", .bold, "a «word» b"),
        ("a «**word**» b", .bold, "a «word» b"),
        ("a «word » b", .bold, "a **«word»**  b"),
        ("a |", .bold, "a **|**"),
        ("a **|**", .bold, "a |"),
        ("«word»", .italic, "*«word»*"),
        ("**«word»**", .italic, "***«word»***"),
        ("***«word»***", .italic, "**«word»**"),
        ("«word»", .underline, "<u>«word»</u>"),
        ("<u>«word»</u>", .underline, "«word»"),
        ("«x»", .strikethrough, "~~«x»~~"),
        ("«x»", .code, "`«x»`"),
        ("«one\ntwo»", .bold, "«**one**\n**two**»"),
        ("«- a\n# Title\n> q»", .bold, "«- **a**\n# **Title**\n> **q**»"),
        ("«- item»", .italic, "«- *item*»"),
        ("«žluť 🙂»", .bold, "**«žluť 🙂»**"),
    ])
    func toggle(input: String, style: InlineStyle, expected: String) {
        #expect(Marked.apply(input) { EditCommand.toggle(style, in: $0, selection: $1) } == expected)
    }
}

struct BlockStyleTests {
    @Test(arguments: [
        ("Title|", BlockStyle.heading(1), "# Title|"),
        ("# Title|", .heading(1), "Title|"),
        ("# Tit|le", .heading(2), "## Tit|le"),
        ("## Title|", .paragraph, "Title|"),
        ("«one\ntwo»", .bulletList, "«- one\n- two»"),
        ("«- one\n- two»", .bulletList, "«one\ntwo»"),
        ("«one\n\ntwo»", .numberedList, "«1. one\n\n2. two»"),
        ("«- one\n- two»", .numberedList, "«1. one\n2. two»"),
        ("|", .taskList, "- [ ] |"),
        ("- [x] done|", .taskList, "done|"),
        ("  - nested|", .numberedList, "  1. nested|"),
        ("quote|", .quote, "> quote|"),
        ("> quote|", .quote, "quote|"),
        ("«a\r\nb»", .bulletList, "«- a\r\n- b»"),
        ("a\n|", .heading(1), "a\n# |"),
    ])
    func setBlock(input: String, style: BlockStyle, expected: String) {
        #expect(Marked.apply(input) { EditCommand.setBlock(style, in: $0, selection: $1) } == expected)
    }
}

struct InsertionTests {
    @Test func link() {
        #expect(Marked.apply("see «docs»") { EditCommand.link(in: $0, selection: $1) } == "see [docs](«url»)")
        #expect(Marked.apply("see |") { EditCommand.link(in: $0, selection: $1) } == "see [«text»](url)")
        #expect(Marked.apply("|") { EditCommand.image(in: $0, selection: $1) } == "![«alt»](url)")
    }

    @Test func blocks() {
        #expect(Marked.apply("|") { EditCommand.horizontalRule(in: $0, selection: $1) } == "---|")
        #expect(Marked.apply("text|") { EditCommand.horizontalRule(in: $0, selection: $1) } == "text\n\n---|")
        #expect(Marked.apply("a\n|\nb") { EditCommand.horizontalRule(in: $0, selection: $1) } == "a\n\n---|\n\nb")
        #expect(Marked.apply("|") { EditCommand.codeBlock(in: $0, selection: $1) } == "```\n|\n```")
        #expect(Marked.apply("«let a = 1»") { EditCommand.codeBlock(in: $0, selection: $1) }
                == "```|\nlet a = 1\n```")
        #expect(Marked.apply("|") { EditCommand.table(in: $0, selection: $1) }
                == "| «Column» | Column |\n|--------|--------|\n|        |        |")
    }
}

struct TypingBehaviorTests {
    @Test(arguments: [
        ("a |", "(", "a (|)"),
        ("a |b", "(", "unchanged"),
        ("a |)", ")", "a )|"),
        ("say |", "\"", "say \"|\""),
        ("word|", "\"", "unchanged"),
        ("«x»", "[", "[«x»]"),
        ("«x»", "*", "*«x»*"),
        ("|", "*", "unchanged"),
        ("|", "ž", "unchanged"),
    ])
    func pairing(input: String, typed: String, expected: String) {
        #expect(Marked.apply(input) { TypingBehavior.insert(typed, in: $0, selection: $1) } == expected)
    }

    @Test func deleteEmptyPair() {
        #expect(Marked.apply("a (|)") { TypingBehavior.deleteBackward(in: $0, selection: $1) } == "a |")
        #expect(Marked.apply("a (x|)") { TypingBehavior.deleteBackward(in: $0, selection: $1) } == "unchanged")
    }

    @Test(arguments: [
        ("- one|", "- one\n- |"),
        ("* one|", "* one\n* |"),
        ("9. nine|", "9. nine\n10. |"),
        ("3) x|", "3) x\n4) |"),
        ("- [x] done|", "- [x] done\n- [ ] |"),
        ("  - nested|", "  - nested\n  - |"),
        ("> quote|", "> quote\n> |"),
        ("> - both|", "> - both\n> - |"),
        ("- |", "|"),
        ("  - |", "  |"),
        ("> |", "|"),
        ("- sp|lit", "- sp\n- |lit"),
        ("plain|", "unchanged"),
        ("# Heading|", "unchanged"),
    ])
    func newline(input: String, expected: String) {
        #expect(Marked.apply(input) { TypingBehavior.newline(in: $0, selection: $1, lineEnding: "\n") } == expected)
    }

    @Test func newlineKeepsCRLF() {
        #expect(Marked.apply("- a|") { TypingBehavior.newline(in: $0, selection: $1, lineEnding: "\r\n") }
                == "- a\r\n- |")
    }

    @Test(arguments: [
        ("- a\n- b|", false, "- a\n  - b|"),
        ("1. a\n2. b|", false, "1. a\n   2. b|"),
        ("- a\n  - b|", true, "- a\n- b|"),
        ("plain|", false, "unchanged"),
    ])
    func indent(input: String, outdent: Bool, expected: String) {
        #expect(Marked.apply(input) { TypingBehavior.indent(in: $0, selection: $1, outdent: outdent) } == expected)
    }
}
