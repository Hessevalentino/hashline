import Foundation

/// Insertions from the editor's context menu. Some need more than one replacement (a footnote
/// reference plus its definition); they return edits to apply in order, as one undo step.
/// Each edit's range is in the text as left by the edits before it.
public enum InsertCommand {
    /// `[^n]` at the caret and `[^n]: ` at the end of the document; the caret goes to the definition.
    public static func footnote(in text: NSString, selection: NSRange, lineEnding: String = "\n") -> [TextEdit] {
        let number = nextFootnoteNumber(in: text)
        let reference = "[^\(number)]"
        let endsWithBreak = text.length > 0 && [0x0A, 0x0D].contains(text.character(at: text.length - 1))
        // Definitions follow each other directly; otherwise a blank line separates them from the text.
        let lastLine = text.substring(with: text.lineRange(for: NSRange(location: max(text.length - 1, 0), length: 0)))
        let followsDefinition = lastLine.hasPrefix("[^") && lastLine.contains("]:")
        let separator: String
        if followsDefinition {
            separator = endsWithBreak ? "" : lineEnding
        } else {
            separator = endsWithBreak ? lineEnding : lineEnding + lineEnding
        }
        let definition = separator + "[^\(number)]: "

        // Definition first (at the end), so the reference edit's range is unaffected.
        let atEnd = NSRange(location: text.length, length: 0)
        let referenceLength = (reference as NSString).length
        let caret = text.length - selection.length + referenceLength + (definition as NSString).length
        return [
            TextEdit(range: atEnd, replacement: definition, selection: atEnd),
            TextEdit(range: selection, replacement: reference, selection: NSRange(location: caret, length: 0)),
        ]
    }

    static func nextFootnoteNumber(in text: NSString) -> Int {
        guard let pattern = try? NSRegularExpression(pattern: #"\[\^(\d+)\]"#) else { return 1 }
        let numbers = pattern.matches(in: text as String, range: NSRange(location: 0, length: text.length))
            .compactMap { Int(text.substring(with: $0.range(at: 1))) }
        return (numbers.max() ?? 0) + 1
    }

    /// `$$` block with the caret inside (rendered from F3).
    public static func mathBlock(in text: NSString, selection: NSRange, lineEnding: String = "\n") -> TextEdit {
        EditCommand.insertBlock("$$" + lineEnding + lineEnding + "$$", caretOffset: 2 + (lineEnding as NSString).length,
                                in: text, at: selection.location, lineEnding: lineEnding)
    }

    /// `[toc]` placeholder for a generated table of contents (rendered from F3).
    public static func tableOfContents(in text: NSString, selection: NSRange, lineEnding: String = "\n") -> TextEdit {
        EditCommand.insertBlock("[toc]", caretOffset: 5, in: text, at: selection.location, lineEnding: lineEnding)
    }

    /// YAML front matter at the top of the document. When it exists, only moves the caret into it.
    public static func frontMatter(in text: NSString, selection: NSRange, lineEnding: String = "\n") -> TextEdit {
        let existing = text.hasPrefix("---" + lineEnding) || text.hasPrefix("---\n")
        if existing {
            let caret = min((("---" + lineEnding) as NSString).length, text.length)
            return TextEdit(range: NSRange(location: 0, length: 0), replacement: "",
                            selection: NSRange(location: caret, length: 0))
        }
        let block = "---" + lineEnding + "title: " + lineEnding + "---" + lineEnding
        let separator = text.length == 0 ? "" : lineEnding
        let caret = (("---" + lineEnding + "title: ") as NSString).length
        return TextEdit(range: NSRange(location: 0, length: 0), replacement: block + separator,
                        selection: NSRange(location: caret, length: 0))
    }

    /// Pasting a URL over selected text makes a link: `[selection](url)`.
    public static func linkFromPastedURL(_ url: String, in text: NSString, selection: NSRange) -> TextEdit? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selection.length > 0, !trimmed.contains(where: \.isWhitespace),
              let parsed = URL(string: trimmed), let scheme = parsed.scheme?.lowercased(),
              ["http", "https", "mailto", "ftp"].contains(scheme) else { return nil }
        let label = text.substring(with: selection)
        guard !label.contains("\n") else { return nil }
        let replacement = "[\(label)](\(trimmed))"
        return TextEdit(range: selection, replacement: replacement,
                        selection: NSRange(location: selection.location + (replacement as NSString).length, length: 0))
    }
}
