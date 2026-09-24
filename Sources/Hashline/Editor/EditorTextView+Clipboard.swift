import AppKit
import HashlineCore

/// Insert menu items, smart paste and "Copy as…".
extension EditorTextView {
    // MARK: Insert

    @objc func insertFootnote(_ sender: Any?) {
        run(name: "Footnote") { [lineEnding] in
            InsertCommand.footnote(in: $0, selection: $1, lineEnding: lineEnding.rawValue)
        }
    }

    @objc func insertMathBlock(_ sender: Any?) {
        run(name: "Math Block") { [lineEnding] in
            [InsertCommand.mathBlock(in: $0, selection: $1, lineEnding: lineEnding.rawValue)]
        }
    }

    @objc func insertTableOfContents(_ sender: Any?) {
        run(name: "Table of Contents") { [lineEnding] in
            [InsertCommand.tableOfContents(in: $0, selection: $1, lineEnding: lineEnding.rawValue)]
        }
    }

    @objc func insertFrontMatter(_ sender: Any?) {
        run(name: "Front Matter") { [lineEnding] in
            [InsertCommand.frontMatter(in: $0, selection: $1, lineEnding: lineEnding.rawValue)]
        }
    }

    // MARK: Paste

    /// URL over a selection becomes a link; HTML (browsers, Word, mail) is converted to Markdown.
    /// Paste and Match Style (⌥⇧⌘V) always inserts plain text.
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard isEditable, let storage = textStorage else { return super.paste(sender) }
        let text = storage.mutableString
        let selection = selectedRange()

        if ImageInsertion.hasImages(pasteboard) {
            insertImages(from: pasteboard)
            return
        }
        if let string = pasteboard.string(forType: .string),
           let edit = InsertCommand.linkFromPastedURL(string, in: text, selection: selection) {
            breakUndoCoalescing()
            apply(edit, actionName: "Paste Link")
            return
        }
        if let html = pasteboard.string(forType: .html), !Self.isPreformattedSource(html),
           let markdown = HTMLToMarkdown.convert(html) {
            let normalized = lineEnding == .lf ? markdown : markdown.replacingOccurrences(of: "\n",
                                                                                         with: lineEnding.rawValue)
            let end = NSRange(location: selection.location + (normalized as NSString).length, length: 0)
            breakUndoCoalescing()
            apply(TextEdit(range: selection, replacement: normalized, selection: end), actionName: "Paste")
            return
        }
        super.paste(sender)
    }

    /// Code editors put syntax-coloured HTML with `white-space: pre` on the pasteboard;
    /// converting it would lose indentation, so their plain text is used instead.
    static func isPreformattedSource(_ html: String) -> Bool {
        let compact = html.lowercased().replacingOccurrences(of: " ", with: "")
        return compact.contains("white-space:pre")
    }

    // MARK: Copy as

    @objc func copyAsMarkdown(_ sender: Any?) {
        guard let markdown = selectedMarkdown() else { return }
        write(string: markdown)
    }

    @objc func copyAsHTML(_ sender: Any?) {
        guard let markdown = selectedMarkdown() else { return }
        let html = PlainTextRenderer.html(from: markdown)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(html, forType: .html)
        pasteboard.setString(html, forType: .string)
    }

    @objc func copyAsPlainText(_ sender: Any?) {
        guard let markdown = selectedMarkdown() else { return }
        write(string: PlainTextRenderer.plainText(from: markdown))
    }

    private func selectedMarkdown() -> String? {
        guard let storage = textStorage else { return nil }
        let selection = selectedRange()
        // Without a selection the whole document is copied.
        let range = selection.length > 0 ? selection : NSRange(location: 0, length: storage.length)
        return storage.mutableString.substring(with: range)
    }

    private func write(string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let insert = NSMenu(title: String(localized: "Insert"))
        let insertItems: [(LocalizedStringResource, Selector)] = [
            ("Image", #selector(insertMarkdownImage(_:))),
            ("Footnote", #selector(insertFootnote(_:))),
            ("Horizontal Rule", #selector(insertHorizontalRule(_:))),
            ("Table", #selector(insertTable(_:))),
            ("Code Block", #selector(insertCodeBlock(_:))),
            ("Math Block", #selector(insertMathBlock(_:))),
            ("Table of Contents", #selector(insertTableOfContents(_:))),
            ("YAML Front Matter", #selector(insertFrontMatter(_:))),
        ]
        for (title, action) in insertItems {
            insert.addItem(withTitle: String(localized: title), action: action, keyEquivalent: "")
        }
        let copy = NSMenu(title: String(localized: "Copy As"))
        copy.addItem(withTitle: "Markdown", action: #selector(copyAsMarkdown(_:)), keyEquivalent: "")
        copy.addItem(withTitle: "HTML", action: #selector(copyAsHTML(_:)), keyEquivalent: "")
        copy.addItem(withTitle: String(localized: "Plain Text"), action: #selector(copyAsPlainText(_:)),
                     keyEquivalent: "")

        let insertItem = NSMenuItem(title: String(localized: "Insert"), action: nil, keyEquivalent: "")
        insertItem.submenu = insert
        let copyItem = NSMenuItem(title: String(localized: "Copy As"), action: nil, keyEquivalent: "")
        copyItem.submenu = copy
        menu.insertItem(insertItem, at: 0)
        menu.insertItem(copyItem, at: 1)
        menu.insertItem(.separator(), at: 2)
        return menu
    }
}
