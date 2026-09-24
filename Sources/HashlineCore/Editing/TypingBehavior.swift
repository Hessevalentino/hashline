import Foundation

/// Automatic edits while typing. Each returns nil when the default text-view behaviour applies.
public enum TypingBehavior {
    static let pairs: [Character: Character] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "`": "`"]
    static let closers: Set<Character> = [")", "]", "}", "\"", "`"]
    /// Markers that wrap a selection when typed over it, but are never auto-paired (`* ` starts a list).
    static let wrappers: Set<Character> = ["*", "_", "~"]

    // MARK: Pairing

    public static func insert(_ typed: String, in text: NSString, selection: NSRange) -> TextEdit? {
        guard typed.count == 1, let character = typed.first else { return nil }
        let next = text.character(atOffset: NSMaxRange(selection))
        let previous = text.character(atOffset: selection.location - 1)

        if selection.length > 0, let closer = pairs[character] ?? (wrappers.contains(character) ? character : nil) {
            let inner = text.substring(with: selection)
            let open = String(character)
            return TextEdit(range: selection, replacement: open + inner + String(closer),
                            selection: NSRange(location: selection.location + 1, length: selection.length))
        }
        guard selection.length == 0 else { return nil }

        // Typing a closer that is already there steps over it.
        if closers.contains(character), next == character {
            return TextEdit(range: NSRange(location: selection.location, length: 0), replacement: "",
                            selection: NSRange(location: selection.location + 1, length: 0))
        }
        guard let closer = pairs[character] else { return nil }
        // Pair only where a pair makes sense: not before a word, and quotes not inside a word.
        if let next, !(next.isWhitespace || next.isPunctuation) { return nil }
        if character == "\"" || character == "`", let previous, previous.isLetter || previous.isNumber { return nil }
        return TextEdit(range: selection, replacement: String(character) + String(closer),
                        selection: NSRange(location: selection.location + 1, length: 0))
    }

    /// Backspace between an empty pair deletes both characters.
    public static func deleteBackward(in text: NSString, selection: NSRange) -> TextEdit? {
        guard selection.length == 0, selection.location > 0,
              let previous = text.character(atOffset: selection.location - 1),
              let closer = pairs[previous], text.character(atOffset: selection.location) == closer else { return nil }
        let range = NSRange(location: selection.location - 1, length: 2)
        return TextEdit(range: range, replacement: "", selection: NSRange(location: range.location, length: 0))
    }

    // MARK: Lists and quotes

    /// Return in a list item or quote continues it; Return on an empty item ends the list.
    public static func newline(in text: NSString, selection: NSRange, lineEnding: String) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let line = text.lines(in: selection)[0].content
        let prefix = LinePrefix.parse(text.substring(with: line))
        guard let marker = prefix.continuation, selection.location >= line.location + prefix.length else { return nil }

        let body = text.substring(with: line).utf16Suffix(from: prefix.length)
        if body.trimmingCharacters(in: .whitespaces).isEmpty {
            // Empty item: remove the marker instead of continuing (keeps outer quote markers).
            let keep = prefix.isListItem ? prefix.indent + prefix.quote : ""
            let range = NSRange(location: line.location, length: line.length)
            return TextEdit(range: range, replacement: keep,
                            selection: NSRange(location: line.location + (keep as NSString).length, length: 0))
        }
        let insertion = lineEnding + prefix.indent + prefix.quote + marker
        return TextEdit(range: selection, replacement: insertion,
                        selection: NSRange(location: selection.location + (insertion as NSString).length, length: 0))
    }

    /// Tab / Shift-Tab on list items indents or outdents every selected item.
    public static func indent(in text: NSString, selection: NSRange, outdent: Bool) -> TextEdit? {
        let lines = text.lines(in: selection)
        let prefixes = lines.map { LinePrefix.parse(text.substring(with: $0.content)) }
        guard prefixes.contains(where: \.isListItem) else { return nil }

        var replacement = ""
        var firstLineShift = 0
        for (index, ((content, terminator), prefix)) in zip(lines, prefixes).enumerated() {
            var line = text.substring(with: content)
            var shift = 0
            if prefix.isListItem {
                if outdent {
                    let removable = min(prefix.indent.prefix { $0 == " " }.count, prefix.nestingWidth)
                    line = String(line.dropFirst(removable))
                    shift = -removable
                } else {
                    let width = previousItemWidth(before: content.location, in: text) ?? prefix.nestingWidth
                    line = String(repeating: " ", count: width) + line
                    shift = width
                }
            }
            if index == 0 { firstLineShift = shift }
            replacement += line + text.substring(with: terminator)
        }
        let first = lines[0].content.location
        let whole = NSRange(location: first, length: NSMaxRange(lines[lines.count - 1].terminator) - first)
        let selectionAfter = selection.length == 0
            ? NSRange(location: max(selection.location + firstLineShift, first), length: 0)
            : NSRange(location: first,
                      length: (replacement as NSString).length - lines[lines.count - 1].terminator.length)
        return TextEdit(range: whole, replacement: replacement, selection: selectionAfter)
    }

    /// Nesting under the previous item needs that item's content column (2 for `- `, 3 for `1. `).
    private static func previousItemWidth(before location: Int, in text: NSString) -> Int? {
        guard location > 0 else { return nil }
        let previous = text.lines(in: NSRange(location: location - 1, length: 0))[0].content
        let prefix = LinePrefix.parse(text.substring(with: previous))
        return prefix.isListItem ? prefix.nestingWidth : nil
    }
}
