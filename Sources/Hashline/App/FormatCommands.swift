import AppKit
import SwiftUI

/// Sends a formatting action to the first responder (the focused editor).
@MainActor
func sendFormatting(_ action: Selector) {
    NSApp.sendAction(action, to: nil, from: nil)
}

/// Format menu. Shortcuts follow Typora where macOS has no convention of its own.
struct FormatCommands: Commands {
    var body: some Commands {
        // Replaces the system Font and Text submenus of the Format menu: a plain-text editor has
        // no use for them, and they claim ⌘B, ⌘I and ⌘U. (A separate CommandMenu("Format")
        // would produce a second Format menu.)
        CommandGroup(replacing: .textFormatting) {
            Button("Bold") { sendFormatting(#selector(EditorTextView.toggleBold(_:))) }
                .keyboardShortcut("b")
            Button("Italic") { sendFormatting(#selector(EditorTextView.toggleItalic(_:))) }
                .keyboardShortcut("i")
            Button("Underline") { sendFormatting(#selector(EditorTextView.toggleUnderlineMarkup(_:))) }
                .keyboardShortcut("u")
            Button("Strikethrough") { sendFormatting(#selector(EditorTextView.toggleStrikethrough(_:))) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Inline Code") { sendFormatting(#selector(EditorTextView.toggleInlineCode(_:))) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Divider()
            Button("Paragraph") { sendFormatting(#selector(EditorTextView.setParagraph(_:))) }
                .keyboardShortcut("0")
            ForEach(HeadingAction.all, id: \.level) { heading in
                Button("Heading \(heading.level)") { sendFormatting(heading.selector) }
                    .keyboardShortcut(KeyEquivalent(Character("\(heading.level)")))
            }
            Divider()
            Button("Bulleted List") { sendFormatting(#selector(EditorTextView.toggleBulletList(_:))) }
                .keyboardShortcut("u", modifiers: [.command, .option])
            Button("Numbered List") { sendFormatting(#selector(EditorTextView.toggleNumberedList(_:))) }
                .keyboardShortcut("o", modifiers: [.command, .option])
            Button("Task List") { sendFormatting(#selector(EditorTextView.toggleTaskList(_:))) }
                .keyboardShortcut("x", modifiers: [.command, .option])
            Button("Quote") { sendFormatting(#selector(EditorTextView.toggleQuote(_:))) }
            Divider()
            Button("Link") { sendFormatting(#selector(EditorTextView.insertMarkdownLink(_:))) }
                .keyboardShortcut("k")
            Button("Image") { sendFormatting(#selector(EditorTextView.insertMarkdownImage(_:))) }
                .keyboardShortcut("i", modifiers: [.command, .control])
            Button("Code Block") { sendFormatting(#selector(EditorTextView.insertCodeBlock(_:))) }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Table") { sendFormatting(#selector(EditorTextView.insertTable(_:))) }
                .keyboardShortcut("t", modifiers: [.command, .control])
            Button("Horizontal Rule") { sendFormatting(#selector(EditorTextView.insertHorizontalRule(_:))) }
            Divider()
            Button("Footnote") { sendFormatting(#selector(EditorTextView.insertFootnote(_:))) }
            Button("Math Block") { sendFormatting(#selector(EditorTextView.insertMathBlock(_:))) }
            Button("Table of Contents") { sendFormatting(#selector(EditorTextView.insertTableOfContents(_:))) }
            Button("YAML Front Matter") { sendFormatting(#selector(EditorTextView.insertFrontMatter(_:))) }
            Divider()
            Menu("Table") {
                Button("Format Table") { sendFormatting(#selector(EditorTextView.formatTable(_:))) }
                Divider()
                Button("Insert Row Above") { sendFormatting(#selector(EditorTextView.insertRowAbove(_:))) }
                Button("Insert Row Below") { sendFormatting(#selector(EditorTextView.insertRowBelow(_:))) }
                Button("Delete Row") { sendFormatting(#selector(EditorTextView.deleteTableRow(_:))) }
                Divider()
                Button("Insert Column Left") { sendFormatting(#selector(EditorTextView.insertColumnLeft(_:))) }
                Button("Insert Column Right") { sendFormatting(#selector(EditorTextView.insertColumnRight(_:))) }
                Button("Delete Column") { sendFormatting(#selector(EditorTextView.deleteTableColumn(_:))) }
                Divider()
                Button("Align Left") { sendFormatting(#selector(EditorTextView.alignColumnLeft(_:))) }
                Button("Align Center") { sendFormatting(#selector(EditorTextView.alignColumnCenter(_:))) }
                Button("Align Right") { sendFormatting(#selector(EditorTextView.alignColumnRight(_:))) }
            }
            Menu("Images") {
                Button("Copy Local Images to Assets Folder") {
                    sendFormatting(#selector(EditorTextView.copyImagesToAssets(_:)))
                }
                Button("Download Remote Images to Assets Folder") {
                    sendFormatting(#selector(EditorTextView.downloadRemoteImages(_:)))
                }
            }
            SyntaxExtensionsMenu()
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy as Markdown") { sendFormatting(#selector(EditorTextView.copyAsMarkdown(_:))) }
            Button("Copy as HTML") { sendFormatting(#selector(EditorTextView.copyAsHTML(_:))) }
            Button("Copy as Plain Text") { sendFormatting(#selector(EditorTextView.copyAsPlainText(_:))) }
        }
    }
}

struct HeadingAction {
    let level: Int
    let selector: Selector

    static let all: [HeadingAction] = [
        HeadingAction(level: 1, selector: #selector(EditorTextView.setHeading1(_:))),
        HeadingAction(level: 2, selector: #selector(EditorTextView.setHeading2(_:))),
        HeadingAction(level: 3, selector: #selector(EditorTextView.setHeading3(_:))),
        HeadingAction(level: 4, selector: #selector(EditorTextView.setHeading4(_:))),
        HeadingAction(level: 5, selector: #selector(EditorTextView.setHeading5(_:))),
        HeadingAction(level: 6, selector: #selector(EditorTextView.setHeading6(_:))),
    ]
}

/// Optional, non-standard syntax (off by default): `==mark==`, `^sup^`, `~sub~`.
struct SyntaxExtensionsMenu: View {
    @AppStorage(SyntaxExtensionSettings.highlightKey) private var highlight = false
    @AppStorage(SyntaxExtensionSettings.superscriptKey) private var superscript = false
    @AppStorage(SyntaxExtensionSettings.subscriptKey) private var subscriptText = false

    var body: some View {
        Menu("Syntax Extensions") {
            Toggle("Highlight ==text==", isOn: $highlight)
            Toggle("Superscript ^text^", isOn: $superscript)
            Toggle("Subscript ~text~", isOn: $subscriptText)
        }
    }
}
