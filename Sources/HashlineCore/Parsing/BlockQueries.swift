import Foundation
import Markdown

/// Questions the editor asks about a block: which task a preview click means, which link is under
/// the pointer.
extension MarkdownBlock {
    /// Toggles the `index`-th task checkbox of the block (document order): `[ ]` ↔ `[x]`.
    public func toggleTask(at index: Int, in text: NSString) -> TextEdit? {
        var tasks: [ListItem] = []
        collectTasks(markup, into: &tasks)
        guard index >= 0, index < tasks.count, let itemRange = range(of: tasks[index]) else { return nil }
        // The checkbox follows the list marker and spaces: `- [ ] text`, `1. [x] text`.
        var cursor = itemRange.location
        let end = min(NSMaxRange(itemRange), text.length)
        while cursor < end, !isSpace(text.character(at: cursor)) { cursor += 1 }
        while cursor < end, isSpace(text.character(at: cursor)) { cursor += 1 }
        guard cursor + 2 < end, text.character(at: cursor) == 0x5B, text.character(at: cursor + 2) == 0x5D else {
            return nil
        }
        let box = NSRange(location: cursor, length: 3)
        let checked = text.substring(with: box).lowercased() == "[x]"
        return TextEdit(range: box, replacement: checked ? "[ ]" : "[x]",
                        selection: NSRange(location: NSMaxRange(box), length: 0))
    }

    private func collectTasks(_ node: Markup, into tasks: inout [ListItem]) {
        if let item = node as? ListItem, item.checkbox != nil { tasks.append(item) }
        for child in node.children { collectTasks(child, into: &tasks) }
    }

    /// Destination of the link (or GFM autolink) at a document offset.
    public func link(at offset: Int, in text: NSString) -> String? {
        guard NSLocationInRange(offset, range) || offset == NSMaxRange(range) else { return nil }
        var found: String?
        findLink(markup, at: offset, in: text, found: &found)
        return found
    }

    private func findLink(_ node: Markup, at offset: Int, in text: NSString, found: inout String?) {
        guard found == nil else { return }
        if let link = node as? Link, let linkRange = range(of: link), NSLocationInRange(offset, linkRange) {
            found = link.destination
            return
        }
        if let textNode = node as? Text, let textRange = range(of: textNode), NSLocationInRange(offset, textRange),
           text.substring(with: textRange) == textNode.string {
            found = Autolinker.matches(in: textNode.string).first {
                NSLocationInRange(offset - textRange.location, $0.range)
            }?.url
            return
        }
        for child in node.children { findLink(child, at: offset, in: text, found: &found) }
    }

    private func isSpace(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09
    }
}
