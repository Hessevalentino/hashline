import AppKit
import HashlineCore

/// Formatting actions. The toolbar and the Format menu send them to the first responder,
/// so they always act on the focused editor.
extension EditorTextView {
    @objc func toggleBold(_ sender: Any?) { perform(inline: .bold, name: "Bold") }
    @objc func toggleItalic(_ sender: Any?) { perform(inline: .italic, name: "Italic") }
    @objc func toggleUnderlineMarkup(_ sender: Any?) { perform(inline: .underline, name: "Underline") }
    @objc func toggleStrikethrough(_ sender: Any?) { perform(inline: .strikethrough, name: "Strikethrough") }
    @objc func toggleInlineCode(_ sender: Any?) { perform(inline: .code, name: "Code") }

    @objc func setParagraph(_ sender: Any?) { perform(block: .paragraph, name: "Paragraph") }
    @objc func setHeading1(_ sender: Any?) { perform(block: .heading(1), name: "Heading") }
    @objc func setHeading2(_ sender: Any?) { perform(block: .heading(2), name: "Heading") }
    @objc func setHeading3(_ sender: Any?) { perform(block: .heading(3), name: "Heading") }
    @objc func setHeading4(_ sender: Any?) { perform(block: .heading(4), name: "Heading") }
    @objc func setHeading5(_ sender: Any?) { perform(block: .heading(5), name: "Heading") }
    @objc func setHeading6(_ sender: Any?) { perform(block: .heading(6), name: "Heading") }
    @objc func toggleBulletList(_ sender: Any?) { perform(block: .bulletList, name: "Bulleted List") }
    @objc func toggleNumberedList(_ sender: Any?) { perform(block: .numberedList, name: "Numbered List") }
    @objc func toggleTaskList(_ sender: Any?) { perform(block: .taskList, name: "Task List") }
    @objc func toggleQuote(_ sender: Any?) { perform(block: .quote, name: "Quote") }

    @objc func insertMarkdownLink(_ sender: Any?) {
        run(name: "Link") { EditCommand.link(in: $0, selection: $1) }
    }

    @objc func insertMarkdownImage(_ sender: Any?) {
        run(name: "Image") { EditCommand.image(in: $0, selection: $1) }
    }

    @objc func insertCodeBlock(_ sender: Any?) {
        run(name: "Code Block") { [lineEnding] in
            EditCommand.codeBlock(in: $0, selection: $1, lineEnding: lineEnding.rawValue)
        }
    }

    @objc func insertTable(_ sender: Any?) {
        run(name: "Table") { [lineEnding] in
            EditCommand.table(in: $0, selection: $1, lineEnding: lineEnding.rawValue)
        }
    }

    @objc func insertHorizontalRule(_ sender: Any?) {
        run(name: "Horizontal Rule") { [lineEnding] in
            EditCommand.horizontalRule(in: $0, selection: $1, lineEnding: lineEnding.rawValue)
        }
    }

    private func perform(inline style: InlineStyle, name: LocalizedStringResource) {
        run(name: name) { EditCommand.toggle(style, in: $0, selection: $1) }
    }

    private func perform(block style: BlockStyle, name: LocalizedStringResource) {
        run(name: name) { EditCommand.setBlock(style, in: $0, selection: $1) }
    }

    /// A command is its own undo step, separate from surrounding typing.
    private func run(name: LocalizedStringResource, _ command: (NSString, NSRange) -> TextEdit) {
        run(name: name) { [command($0, $1)] }
    }

    /// Several edits (e.g. footnote reference + definition) grouped into one undo step.
    /// `name` is the undo menu title (“Undo Bold”), localized.
    func run(name: LocalizedStringResource, _ command: (NSString, NSRange) -> [TextEdit]) {
        guard isEditable, let storage = textStorage else { return }
        let edits = command(storage.mutableString, selectedRange())
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        for edit in edits { apply(edit) }
        undoManager?.setActionName(String(localized: name))
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()
    }

    /// Replaces text through the text view so undo, the document's dirty state and highlighting all follow.
    func apply(_ edit: TextEdit, actionName: LocalizedStringResource? = nil) {
        guard let storage = textStorage,
              shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        storage.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
        if let actionName { undoManager?.setActionName(String(localized: actionName)) }
    }
}
