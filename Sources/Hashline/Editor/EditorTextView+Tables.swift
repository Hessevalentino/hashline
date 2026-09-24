import AppKit
import HashlineCore

/// Table editing and emoji completion.
extension EditorTextView {
    // MARK: Tables

    @objc func formatTable(_ sender: Any?) {
        runTable("Format Table") { TableCommand.format(in: $0, selection: $1, lineEnding: $2) }
    }

    @objc func insertRowAbove(_ sender: Any?) {
        runTable("Insert Row") { TableCommand.insertRow(in: $0, selection: $1, below: false, lineEnding: $2) }
    }

    @objc func insertRowBelow(_ sender: Any?) {
        runTable("Insert Row") { TableCommand.insertRow(in: $0, selection: $1, below: true, lineEnding: $2) }
    }

    @objc func deleteTableRow(_ sender: Any?) {
        runTable("Delete Row") { TableCommand.deleteRow(in: $0, selection: $1, lineEnding: $2) }
    }

    @objc func insertColumnLeft(_ sender: Any?) {
        runTable("Insert Column") { TableCommand.insertColumn(in: $0, selection: $1, right: false, lineEnding: $2) }
    }

    @objc func insertColumnRight(_ sender: Any?) {
        runTable("Insert Column") { TableCommand.insertColumn(in: $0, selection: $1, right: true, lineEnding: $2) }
    }

    @objc func deleteTableColumn(_ sender: Any?) {
        runTable("Delete Column") { TableCommand.deleteColumn(in: $0, selection: $1, lineEnding: $2) }
    }

    @objc func alignColumnLeft(_ sender: Any?) { align(.left) }
    @objc func alignColumnCenter(_ sender: Any?) { align(.center) }
    @objc func alignColumnRight(_ sender: Any?) { align(.right) }

    private func align(_ alignment: MarkdownTable.Alignment) {
        runTable("Align") { TableCommand.align(alignment, in: $0, selection: $1, lineEnding: $2) }
    }

    var isInTable: Bool {
        guard let storage = textStorage else { return false }
        return TableCommand.format(in: storage.mutableString, selection: selectedRange()) != nil
    }

    private func runTable(_ name: LocalizedStringResource,
                          _ command: @escaping (NSString, NSRange, String) -> TextEdit?) {
        let ending = lineEnding.rawValue
        run(name: name) { text, selection in command(text, selection, ending).map { [$0] } ?? [] }
    }

    /// Tab / Shift-Tab inside a table: format and move between cells.
    func tableTab(backwards: Bool) -> Bool {
        guard let storage = textStorage,
              let edit = TableCommand.moveCell(in: storage.mutableString, selection: selectedRange(),
                                               backwards: backwards, lineEnding: lineEnding.rawValue)
        else { return false }
        breakUndoCoalescing()
        apply(edit, actionName: "Next Cell")
        return true
    }

    // MARK: Emoji completion (":smi" → 😄)

    /// `:` followed by at least two shortcode characters directly before the caret.
    func emojiCompletionRange() -> NSRange? {
        guard let storage = textStorage, selectedRange().length == 0 else { return nil }
        let text = storage.mutableString
        let caret = selectedRange().location
        var start = caret
        while start > 0, start > caret - 40 {
            let unit = text.character(at: start - 1)
            guard let scalar = UnicodeScalar(unit) else { break }
            let isNameCharacter = CharacterSet.alphanumerics.contains(scalar) || [0x5F, 0x2B, 0x2D].contains(unit)
            guard isNameCharacter else { break }
            start -= 1
        }
        guard start > 0, text.character(at: start - 1) == 0x3A, caret - start >= 2 else { return nil }
        // Not part of a URL like `https://`.
        if start >= 2, text.character(at: start - 2) != 0x20, text.character(at: start - 2) != 0x0A,
           let previous = UnicodeScalar(text.character(at: start - 2)),
           CharacterSet.alphanumerics.contains(previous) { return nil }
        return NSRange(location: start - 1, length: caret - start + 1)
    }

    override var rangeForUserCompletion: NSRange {
        emojiCompletionRange() ?? super.rangeForUserCompletion
    }

    override func completions(forPartialWordRange charRange: NSRange,
                              indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        guard let storage = textStorage, let range = emojiCompletionRange(), range == charRange else {
            return super.completions(forPartialWordRange: charRange, indexOfSelectedItem: index)
        }
        let prefix = String(storage.mutableString.substring(with: range).dropFirst())
        index.pointee = 0
        return Emoji.completions(for: prefix).map { "\($0.emoji) :\($0.name):" }
    }

    /// The list shows "😄 :smile:"; the document gets the emoji character itself.
    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange,
                                   movement: Int, isFinal flag: Bool) {
        guard emojiCompletionRange() == charRange || word.contains(" :") else {
            return super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
        }
        let emoji = word.components(separatedBy: " :").first ?? word
        super.insertCompletion(flag ? emoji : word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
    }
}
