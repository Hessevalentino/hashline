import AppKit

/// Thin formatting bar in the window's title area (ADR 0006), built with AppKit: a SwiftUI
/// `.toolbar` with these items added ~130 ms to opening a document (A/B measured 2026-09-24).
/// Items send their actions to the first responder, i.e. the focused editor, which also validates them.
/// Hidden with View ▸ Hide Toolbar (⌥⌘T); customisable via the context menu.
@MainActor
final class FormatToolbar: NSObject, NSToolbarDelegate, NSSharingServicePickerToolbarItemDelegate {
    private weak var window: NSWindow?
    private struct Item {
        let identifier: NSToolbarItem.Identifier
        let title: LocalizedStringResource
        let symbol: String
        let action: Selector?
        let shortcut: String?
    }

    /// Bumped when default items are added: a saved customisation would otherwise hide them.
    private static let identifier = NSToolbar.Identifier("cz.hashline.format.3")

    private static func id(_ raw: String) -> NSToolbarItem.Identifier { .init("cz.hashline.toolbar.\(raw)") }

    private static let library = id("library")
    private static let heading = id("heading")
    private static let list = id("list")
    private static let preview = id("preview")
    private static let share = id("share")
    private static let appearance = id("appearance")
    private static let reading = id("reading")

    private static let buttons: [Item] = [
        Item(identifier: id("bold"), title: "Bold", symbol: "bold",
             action: #selector(EditorTextView.toggleBold(_:)), shortcut: "⌘B"),
        Item(identifier: id("italic"), title: "Italic", symbol: "italic",
             action: #selector(EditorTextView.toggleItalic(_:)), shortcut: "⌘I"),
        Item(identifier: id("underline"), title: "Underline", symbol: "underline",
             action: #selector(EditorTextView.toggleUnderlineMarkup(_:)), shortcut: "⌘U"),
        Item(identifier: id("quote"), title: "Quote", symbol: "text.quote",
             action: #selector(EditorTextView.toggleQuote(_:)), shortcut: nil),
        Item(identifier: id("code"), title: "Inline Code", symbol: "chevron.left.forwardslash.chevron.right",
             action: #selector(EditorTextView.toggleInlineCode(_:)), shortcut: "⇧⌘C"),
        Item(identifier: id("codeBlock"), title: "Code Block", symbol: "curlybraces",
             action: #selector(EditorTextView.insertCodeBlock(_:)), shortcut: "⌥⌘C"),
        Item(identifier: id("link"), title: "Link", symbol: "link",
             action: #selector(EditorTextView.insertMarkdownLink(_:)), shortcut: "⌘K"),
        Item(identifier: id("image"), title: "Image", symbol: "photo",
             action: #selector(EditorTextView.insertMarkdownImage(_:)), shortcut: "⌃⌘I"),
        Item(identifier: id("table"), title: "Table", symbol: "tablecells",
             action: #selector(EditorTextView.insertTable(_:)), shortcut: "⌃⌘T"),
        Item(identifier: id("rule"), title: "Horizontal Rule", symbol: "minus",
             action: #selector(EditorTextView.insertHorizontalRule(_:)), shortcut: nil),
    ]

    /// Formatting items, centred in the window as one group.
    private static let formatting: [NSToolbarItem.Identifier] =
        buttons.prefix(3).map(\.identifier) + [heading, list] + buttons.dropFirst(3).map(\.identifier)

    private static let defaultOrder: [NSToolbarItem.Identifier] =
        [library, .flexibleSpace] + formatting + [.flexibleSpace, appearance, share, reading, preview]

    /// An empty bar of the same style, installed before the first display so the title bar
    /// already has its final height; `install(in:)` replaces it once the editor is editable.
    static func installPlaceholder(in window: NSWindow) {
        guard window.toolbar == nil || window.toolbar?.identifier != identifier else { return }
        window.toolbar = NSToolbar(identifier: "cz.hashline.placeholder")
        window.toolbarStyle = .unifiedCompact
        separateContent(in: window)
    }

    /// Content starts below the title bar: split dividers and the library's background would
    /// otherwise run up through the toolbar and move with every divider drag.
    private static func separateContent(in window: NSWindow) {
        guard window.styleMask.contains(.fullSizeContentView) else { return }
        // Keep the window's frame (restored by SwiftUI); the content shrinks by the title bar.
        let frame = window.frame
        window.styleMask.remove(.fullSizeContentView)
        window.setFrame(frame, display: false)
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .line
    }

    /// Installs the bar once per window. Creating the items (13 SF Symbols, layout) costs about
    /// 75 ms, so it runs after the editor is editable rather than on the open path.
    static func install(in window: NSWindow) -> FormatToolbar? {
        guard window.toolbar?.identifier != identifier else { return nil }
        let controller = FormatToolbar()
        controller.window = window
        let toolbar = NSToolbar(identifier: identifier)
        toolbar.delegate = controller
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.centeredItemIdentifiers = Set(formatting)
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
        separateContent(in: window)
        // Documents opened from the library join this window as tabs.
        window.tabbingMode = .preferred
        return controller
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.defaultOrder
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.defaultOrder + [.flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case Self.library:
            let item = button(Item(identifier: identifier, title: "Library", symbol: "sidebar.left",
                                   action: #selector(toggleLibrary(_:)), shortcut: "⇧⌘L"))
            item.target = self
            item.autovalidates = false
            return item
        case Self.heading:
            let entries: [(LocalizedStringResource, Selector)] =
                [("Paragraph", #selector(EditorTextView.setParagraph(_:)))]
                + HeadingAction.all.map { ("Heading \($0.level)", $0.selector) }
            return menu(identifier, title: "Heading", symbol: "textformat.size", tip: "Heading (⌘1–⌘6, ⌘0)",
                        entries: entries)
        case Self.list:
            return menu(identifier, title: "List", symbol: "list.bullet", tip: "List", entries: [
                ("Bulleted List", #selector(EditorTextView.toggleBulletList(_:))),
                ("Numbered List", #selector(EditorTextView.toggleNumberedList(_:))),
                ("Task List", #selector(EditorTextView.toggleTaskList(_:))),
            ])
        case Self.appearance:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = String(localized: "Appearance")
            item.paletteLabel = item.label
            item.view = AppearanceSwitchView()
            return item
        case Self.share:
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: identifier)
            item.label = String(localized: "Share")
            item.paletteLabel = item.label
            item.toolTip = String(localized: "Share")
            item.delegate = self
            return item
        case Self.reading:
            let item = button(Item(identifier: identifier, title: "Reading Mode", symbol: "book",
                                   action: #selector(toggleReading(_:)), shortcut: "⌘/"))
            item.target = self
            item.autovalidates = false
            return item
        case Self.preview:
            let item = button(Item(identifier: identifier, title: "Preview", symbol: "rectangle.split.2x1",
                                   action: #selector(togglePreview(_:)), shortcut: "⌥⌘P"))
            item.target = self
            item.autovalidates = false
            return item
        default:
            return Self.buttons.first { $0.identifier == identifier }.map(button)
        }
    }

    private func button(_ spec: Item) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: spec.identifier)
        let title = String(localized: spec.title)
        item.label = title
        item.paletteLabel = title
        item.toolTip = spec.shortcut.map { "\(title) (\($0))" } ?? title
        item.image = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: title)
        item.isBordered = true
        item.action = spec.action  // nil target: first responder
        return item
    }

    private func menu(_ identifier: NSToolbarItem.Identifier, title: LocalizedStringResource, symbol: String,
                      tip: LocalizedStringResource, entries: [(LocalizedStringResource, Selector)]) -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: identifier)
        item.label = String(localized: title)
        item.paletteLabel = item.label
        item.toolTip = String(localized: tip)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.label)
        item.showsIndicator = true
        let menu = NSMenu()
        for (entryTitle, action) in entries {
            menu.addItem(NSMenuItem(title: String(localized: entryTitle), action: action, keyEquivalent: ""))
        }
        item.menu = menu
        return item
    }

    /// Always a `.md` file with the current text, so AirDrop, Mail and Messages send the document itself.
    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        guard let window, let session = DocumentReveal.session(for: window),
              let url = Sharing.markdownFile(for: session) else { return [] }
        return [url]
    }

    @objc private func toggleLibrary(_ sender: Any?) {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: LibrarySettings.showsLibraryKey), forKey: LibrarySettings.showsLibraryKey)
    }

    /// The rendered document alone, as a readable page (View ▸ Reading Mode).
    @objc private func toggleReading(_ sender: Any?) {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: ViewSettings.readingModeKey), forKey: ViewSettings.readingModeKey)
    }

    @objc private func togglePreview(_ sender: Any?) {
        PreviewSettings.togglePreview()
    }
}
