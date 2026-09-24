import Foundation

/// Inline formatting that wraps the selection in markers.
public enum InlineStyle: Sendable, CaseIterable {
    case bold, italic, underline, strikethrough, code

    var open: String {
        switch self {
        case .bold: "**"
        case .italic: "*"
        case .underline: "<u>"
        case .strikethrough: "~~"
        case .code: "`"
        }
    }

    var close: String {
        self == .underline ? "</u>" : open
    }
}

/// Line-level formatting applied to every line the selection touches.
public enum BlockStyle: Sendable, Equatable {
    case paragraph
    case heading(Int)
    case bulletList
    case numberedList
    case taskList
    case quote
}

/// Formatting commands for the toolbar, the Format menu and shortcuts.
/// Pure functions over (text, selection); the text view applies the returned edit.
public enum EditCommand {
    // MARK: Inline

    /// Wraps the selection, or unwraps it when it is already formatted.
    /// Without a selection inserts an empty pair with the caret inside.
    public static func toggle(_ style: InlineStyle, in text: NSString, selection: NSRange) -> TextEdit {
        if selection.length == 0 {
            if isWrapped(style, around: selection, in: text) {
                // Caret inside an empty pair: remove the pair.
                let range = NSRange(location: selection.location - length(style.open),
                                    length: length(style.open) + length(style.close))
                return TextEdit(range: range, replacement: "", selection: NSRange(location: range.location, length: 0))
            }
            let caret = selection.location + length(style.open)
            return TextEdit(range: selection, replacement: style.open + style.close,
                            selection: NSRange(location: caret, length: 0))
        }

        let trimmed = trimmingWhitespace(selection, in: text)
        if isWrapped(style, around: trimmed, in: text) {
            let open = length(style.open)
            let range = NSRange(location: trimmed.location - open, length: trimmed.length + open + length(style.close))
            return TextEdit(range: range, replacement: text.substring(with: trimmed),
                            selection: NSRange(location: range.location, length: trimmed.length))
        }
        let content = text.substring(with: trimmed)
        if content.hasPrefix(style.open), content.hasSuffix(style.close),
           content.count >= style.open.count + style.close.count, markerRun(style, in: content) {
            let inner = String(content.dropFirst(style.open.count).dropLast(style.close.count))
            return TextEdit(range: trimmed, replacement: inner,
                            selection: NSRange(location: trimmed.location, length: length(inner)))
        }
        // Emphasis cannot span lines: wrap each line separately, after its list/heading/quote
        // marker when the selection covers the line start (`**- a**` would break the list).
        let lines = content.components(separatedBy: "\n")
        var lineStart = trimmed.location
        let wrapped = lines.map { line -> String in
            defer { lineStart += length(line) + 1 }
            let startsLine = lineStart == 0 || text.character(at: lineStart - 1) == 0x0A
            let markerLength = startsLine ? LinePrefix.parse(line).length : 0
            let marker = String((line as NSString).substring(to: markerLength))
            let rest = line.utf16Suffix(from: markerLength)
            let body = rest.trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { return line }
            let leading = rest.prefix { $0 == " " || $0 == "\t" }
            let trailing = String(rest.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
            return marker + leading + style.open + body + style.close + trailing
        }.joined(separator: "\n")
        let selectionAfter = lines.count == 1 && wrapped == style.open + content + style.close
            ? NSRange(location: trimmed.location + length(style.open), length: trimmed.length)
            : NSRange(location: trimmed.location, length: length(wrapped))
        return TextEdit(range: trimmed, replacement: wrapped, selection: selectionAfter)
    }

    /// Whether the markers of `style` directly surround `range`. Runs of `*` count so that
    /// italic inside `**bold**` is not mistaken for italic.
    static func isWrapped(_ style: InlineStyle, around range: NSRange, in text: NSString) -> Bool {
        let before = run(of: style.open, endingAt: range.location, in: text)
        let after = run(of: style.close, startingAt: NSMaxRange(range), in: text)
        switch style {
        case .italic: return before % 2 == 1 && after % 2 == 1
        case .bold, .strikethrough: return before >= 2 && after >= 2
        case .code: return before >= 1 && after >= 1
        case .underline: return before >= 1 && after >= 1
        }
    }

    private static func markerRun(_ style: InlineStyle, in content: String) -> Bool {
        guard style == .italic else { return true }
        let leading = content.prefix { $0 == "*" }.count
        return leading % 2 == 1
    }

    /// For single-character markers the length of the run of that character before the offset;
    /// for longer markers 1 when the marker ends there (repeated markers count as multiples).
    private static func run(of marker: String, endingAt offset: Int, in text: NSString) -> Int {
        if marker.count == 1 || marker == "**" || marker == "~~" {
            let unit = (marker as NSString).character(at: 0)
            var count = 0
            while offset - count - 1 >= 0, text.character(at: offset - count - 1) == unit { count += 1 }
            return count
        }
        let markerLength = length(marker)
        guard offset >= markerLength else { return 0 }
        return text.substring(with: NSRange(location: offset - markerLength, length: markerLength)) == marker ? 1 : 0
    }

    private static func run(of marker: String, startingAt offset: Int, in text: NSString) -> Int {
        if marker.count == 1 || marker == "**" || marker == "~~" {
            let unit = (marker as NSString).character(at: 0)
            var count = 0
            while offset + count < text.length, text.character(at: offset + count) == unit { count += 1 }
            return count
        }
        let markerLength = length(marker)
        guard offset + markerLength <= text.length else { return 0 }
        return text.substring(with: NSRange(location: offset, length: markerLength)) == marker ? 1 : 0
    }

    // MARK: Blocks

    /// Applies a line style to every line the selection touches. Applying the style all lines
    /// already have removes it (toggle).
    public static func setBlock(_ style: BlockStyle, in text: NSString, selection: NSRange) -> TextEdit {
        let lines = text.lines(in: selection)
        let prefixes = lines.map { LinePrefix.parse(text.substring(with: $0.content)) }
        let nonEmpty = zip(lines, prefixes).filter { $0.0.content.length > $0.1.length || lines.count == 1 }
        let alreadyStyled = !nonEmpty.isEmpty && nonEmpty.allSatisfy { has(style, $0.1) }
        let target: BlockStyle = alreadyStyled ? .paragraph : style

        let first = lines[0].content.location
        var replacement = ""
        var number = 1
        var caret = selection.location
        for ((content, terminator), prefix) in zip(lines, prefixes) {
            let body = text.substring(with: content).utf16Suffix(from: prefix.length)
            let isBlank = body.trimmingCharacters(in: .whitespaces).isEmpty && lines.count > 1
            let newPrefix = isBlank ? "" : Self.prefix(for: target, keeping: prefix, number: &number)
            if selection.length == 0, selection.location >= content.location,
               selection.location <= NSMaxRange(content) {
                let offsetInBody = max(selection.location - content.location - prefix.length, 0)
                caret = first + length(replacement) + length(newPrefix) + offsetInBody
            }
            replacement += newPrefix + body + text.substring(with: terminator)
        }
        let whole = NSRange(location: first, length: NSMaxRange(lines[lines.count - 1].terminator) - first)
        let trailingBreak = lines[lines.count - 1].terminator.length
        let selectionAfter = selection.length == 0
            ? NSRange(location: caret, length: 0)
            : NSRange(location: first, length: length(replacement) - trailingBreak)
        return TextEdit(range: whole, replacement: replacement, selection: selectionAfter)
    }

    private static func has(_ style: BlockStyle, _ prefix: LinePrefix) -> Bool {
        switch (style, prefix.marker) {
        case (.heading(let level), .heading(let existing)): level == existing
        case (.bulletList, .bullet), (.numberedList, .ordered), (.taskList, .task): true
        case (.quote, _): !prefix.quote.isEmpty
        case (.paragraph, .none): prefix.quote.isEmpty
        default: false
        }
    }

    /// New prefix for a line. List indentation is kept so nested lists stay nested.
    private static func prefix(for style: BlockStyle, keeping old: LinePrefix, number: inout Int) -> String {
        switch style {
        case .paragraph: return ""
        case .heading(let level): return String(repeating: "#", count: min(max(level, 1), 6)) + " "
        case .bulletList: return old.indent + "- "
        case .taskList: return old.indent + "- [ ] "
        case .numberedList:
            defer { number += 1 }
            return old.indent + "\(number). "
        case .quote: return "> "
        }
    }

    // MARK: Insertions

    /// `[selection](url)` with `url` selected, or `[text](url)` with `text` selected.
    public static func link(in text: NSString, selection: NSRange) -> TextEdit {
        wrapWithTarget(opening: "[", closing: "](", target: "url", tail: ")", placeholder: "text",
                       in: text, selection: selection)
    }

    /// `![selection](url)` with `url` selected, or `![alt](url)` with `alt` selected.
    public static func image(in text: NSString, selection: NSRange) -> TextEdit {
        wrapWithTarget(opening: "![", closing: "](", target: "url", tail: ")", placeholder: "alt",
                       in: text, selection: selection)
    }

    // swiftlint:disable:next function_parameter_count
    private static func wrapWithTarget(opening: String, closing: String, target: String, tail: String,
                                       placeholder: String, in text: NSString, selection: NSRange) -> TextEdit {
        let label = selection.length > 0 ? text.substring(with: selection) : placeholder
        let replacement = opening + label + closing + target + tail
        let selectionAfter = selection.length > 0
            ? NSRange(location: selection.location + length(opening + label + closing), length: length(target))
            : NSRange(location: selection.location + length(opening), length: length(label))
        return TextEdit(range: selection, replacement: replacement, selection: selectionAfter)
    }

    /// Fenced code block around the selected lines, or an empty one with the caret inside.
    public static func codeBlock(in text: NSString, selection: NSRange, lineEnding: String = "\n") -> TextEdit {
        if selection.length > 0 {
            let lines = text.lines(in: selection)
            let first = lines[0].content.location
            let lastContent = lines[lines.count - 1].content
            let range = NSRange(location: first, length: NSMaxRange(lastContent) - first)
            let body = text.substring(with: range)
            let replacement = "```" + lineEnding + body + lineEnding + "```"
            return TextEdit(range: range, replacement: replacement,
                            selection: NSRange(location: first + 3, length: 0))
        }
        return insertBlock("```" + lineEnding + lineEnding + "```", caretOffset: 3 + length(lineEnding),
                           in: text, at: selection.location, lineEnding: lineEnding)
    }

    public static func table(in text: NSString, selection: NSRange, lineEnding: String = "\n") -> TextEdit {
        let rows = ["| Column | Column |", "|--------|--------|", "|        |        |"]
        return insertBlock(rows.joined(separator: lineEnding), caretOffset: 2, selectionLength: 6,
                           in: text, at: selection.location, lineEnding: lineEnding)
    }

    public static func horizontalRule(in text: NSString, selection: NSRange, lineEnding: String = "\n") -> TextEdit {
        insertBlock("---", caretOffset: 3, in: text, at: selection.location, lineEnding: lineEnding)
    }

    /// Inserts a block as its own paragraph, adding blank lines where a neighbouring line has text.
    static func insertBlock(_ block: String, caretOffset: Int, selectionLength: Int = 0,
                            in text: NSString, at location: Int, lineEnding: String) -> TextEdit {
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        let current = NSRange(location: start, length: contentsEnd - start)
        let currentIsEmpty = isBlank(current, in: text)
        let previousHasText = start > 0
            && !isBlank(text.lineRange(for: NSRange(location: start - 1, length: 0)), in: text)
        let nextHasText = end < text.length
            && !isBlank(text.lineRange(for: NSRange(location: end, length: 0)), in: text)

        let range: NSRange
        var before = ""
        if currentIsEmpty {
            range = current  // replace the empty line's content
            if previousHasText { before = lineEnding }
        } else {
            range = NSRange(location: contentsEnd, length: 0)  // after the current line
            before = lineEnding + lineEnding
        }
        // The existing line break follows the block; a blank line keeps text below from joining it.
        let after = nextHasText ? lineEnding : ""
        let caret = range.location + length(before) + caretOffset
        return TextEdit(range: range, replacement: before + block + after,
                        selection: NSRange(location: caret, length: selectionLength))
    }

    private static func isBlank(_ range: NSRange, in text: NSString) -> Bool {
        text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Helpers

    static func length(_ string: String) -> Int {
        (string as NSString).length
    }

    private static func trimmingWhitespace(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, isWhitespace(text.character(at: start)) { start += 1 }
        while end > start, isWhitespace(text.character(at: end - 1)) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D
    }
}
