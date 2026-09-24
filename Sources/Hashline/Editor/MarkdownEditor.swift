import AppKit
import HashlineCore
import SwiftUI

/// Source editor: NSTextView on TextKit 2 showing the document's text storage.
/// Highlighting changes attributes only, never the text.
struct MarkdownEditor: NSViewRepresentable {
    let session: EditorSession

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Reading mode takes the editor out of the window; it comes back with its caret and scroll.
        if let scrollView = session.editorScrollView, let textView = scrollView.documentView as? NSTextView {
            textView.delegate = context.coordinator
            context.coordinator.undoManager = context.environment.undoManager
            return scrollView
        }
        let document = session.document
        let textView = EditorTextView(usingTextLayoutManager: true)
        textView.lineEnding = document.lineEnding
        textView.onBecameEditable = { [weak document, weak session] in
            LaunchMetrics.editorBecameEditable()
            if let startedAt = document?.takeOpenStartedAt() {
                let elapsed = (ContinuousClock.now - startedAt).milliseconds
                Performance.logger.notice("Open file to editable: \(elapsed, format: .fixed(precision: 1)) ms")
            }
            session?.editorBecameEditable()
        }
        configure(textView)

        if let contentStorage = textView.textContentStorage {
            contentStorage.textStorage = document.textStorage
        } else {
            Performance.logger.fault("TextKit 2 content storage missing; editor fell back to TextKit 1")
        }

        textView.delegate = context.coordinator
        context.coordinator.undoManager = context.environment.undoManager
        textView.setAccessibilityLabel(String(localized: "Markdown source"))

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.documentView = textView
        session.editorScrollView = scrollView
        session.attach(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.undoManager = context.environment.undoManager
    }

    private func configure(_ textView: NSTextView) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        // Find uses Hashline's own bar (regex, replace with groups); see FindController.
        textView.usesFindBar = false

        // Markdown syntax must stay literal.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        /// The document's undo manager. Routing text edits through it is what
        /// marks the document dirty, so autosave and versions work.
        weak var undoManager: UndoManager?

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            (notification.object as? EditorTextView)?.onSelectionChange?()
        }
    }
}

final class EditorTextView: NSTextView {
    /// Reports the first moment the text view is in a window and first responder.
    var onBecameEditable: (@MainActor @Sendable () -> Void)?
    /// Called synchronously when the view first gets a window, before the first display.
    var onWindowAvailable: ((NSWindow) -> Void)?
    var onAppearanceChange: (() -> Void)?
    /// Destination of the link at a character offset (for ⌘-click).
    var linkAtOffset: ((Int) -> String?)?
    /// Receives the text an edit is about to replace.
    var onSelectionCaptureNeeded: ((String) -> Void)?
    /// Line break inserted by Return, matching the document.
    var lineEnding: LineEnding = .lf
    var onSelectionChange: (() -> Void)?
    var onFindAction: ((NSTextFinder.Action) -> Void)?
    /// Take keyboard focus as soon as the view is back in a window (leaving reading mode).
    var becomesFirstResponderInWindow = false

    override func performTextFinderAction(_ sender: Any?) {
        guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag,
              let action = NSTextFinder.Action(rawValue: tag), let onFindAction else {
            return super.performTextFinderAction(sender)
        }
        onFindAction(action)
    }

    override func performFindPanelAction(_ sender: Any?) {
        performTextFinderAction(sender)
    }
    /// Maximum line length in characters (View ▸ Text Width); 0 = full width. Wide lines are
    /// also slower to lay out on every keystroke.
    var maxLineCharacters = ViewSettings.defaultWidth {
        didSet { updateTextInsets() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTextInsets()
    }

    /// Centres a column of `maxLineCharacters` characters.
    func updateTextInsets() {
        var horizontal: CGFloat = 24
        if maxLineCharacters > 0, let font = typingAttributes[.font] as? NSFont ?? font {
            let characterWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
            let column = CGFloat(maxLineCharacters) * characterWidth + 2 * (textContainer?.lineFragmentPadding ?? 0)
            horizontal = max(24, (bounds.width - column) / 2)
        }
        if abs(textContainerInset.width - horizontal) > 0.5 {
            textContainerInset = NSSize(width: horizontal.rounded(), height: 20)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if becomesFirstResponderInWindow, let window {
            becomesFirstResponderInWindow = false
            window.makeFirstResponder(self)
        }
        if let window, let onWindowAvailable {
            self.onWindowAvailable = nil
            onWindowAvailable(window)
        }
        guard let window, let callback = onBecameEditable else { return }
        onBecameEditable = nil
        window.makeFirstResponder(self)
        // Next runloop turn: the first layout and display pass has happened by then. The preview
        // may have taken first responder while being added; the editor keeps the focus.
        DispatchQueue.main.async { [weak self] in
            if let self { self.window?.makeFirstResponder(self) }
            callback()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if affectedCharRange.length > 0, let storage = textStorage {
            onSelectionCaptureNeeded?(storage.mutableString.substring(with: affectedCharRange))
        }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    // After every edit AppKit enumerates the attributes of the text for its Touch Bar formatting
    // items, even on Macs without a Touch Bar. With syntax highlighting that is thousands of attribute
    // runs per keystroke (88 % of main-thread time when typing in 1 MB, Time Profiler 2026-09-23).
    // Plain-text editing has no use for those items.
    override func updateTextTouchBarItems() {}

    override func makeTouchBar() -> NSTouchBar? {
        nil
    }

    /// ⌘-click opens the link under the pointer; a plain click places the caret as usual.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let linkAtOffset {
            let point = convert(event.locationInWindow, from: nil)
            let offset = characterIndexForInsertion(at: point)
            if let link = linkAtOffset(offset) {
                openLink(link)
                return
            }
        }
        super.mouseDown(with: event)
    }

    private func openLink(_ link: String) {
        if let url = URL(string: link), let scheme = url.scheme?.lowercased() {
            if ["http", "https", "mailto"].contains(scheme) { NSWorkspace.shared.open(url) }
            return
        }
        // Relative link: resolve against the document's folder; Markdown opens in Hashline.
        guard let documentURL = window?.representedURL,
              let path = (link.split(separator: "#").first.map(String.init))?.removingPercentEncoding,
              !path.isEmpty else { return }
        let target = URL(fileURLWithPath: path, relativeTo: documentURL.deletingLastPathComponent()).standardizedFileURL
        if LibraryIndex.extensions.contains(target.pathExtension.lowercased()) {
            NSDocumentController.shared.openDocument(withContentsOf: target, display: true) { _, _, _ in }
        } else {
            NSWorkspace.shared.open(target)
        }
    }

    override func keyDown(with event: NSEvent) {
        let keystroke = TypingLatency.begin()
        super.keyDown(with: event)
        TypingLatency.processingSamples.append((ContinuousClock.now - keystroke.startedAt).milliseconds)
        TypingLatency.endAfterFrameCommit(keystroke)
    }

    // MARK: Typing behaviour (see TypingBehavior)

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // Only plain typing: not while an input method composes (dead keys, IME) and not for
        // explicit replacements.
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string
        if !hasMarkedText(), replacementRange.location == NSNotFound, let typed, let storage = textStorage,
           let edit = TypingBehavior.insert(typed, in: storage.mutableString, selection: selectedRange()) {
            apply(edit)
            return
        }
        super.insertText(string, replacementRange: replacementRange)
        // ":sm" offers emoji; the system completion list handles the rest.
        if !hasMarkedText(), emojiCompletionRange() != nil { complete(nil) }
    }

    override func deleteBackward(_ sender: Any?) {
        if let storage = textStorage,
           let edit = TypingBehavior.deleteBackward(in: storage.mutableString, selection: selectedRange()) {
            apply(edit)
            return
        }
        super.deleteBackward(sender)
    }

    override func insertNewline(_ sender: Any?) {
        if let storage = textStorage, let edit = TypingBehavior.newline(
            in: storage.mutableString, selection: selectedRange(), lineEnding: lineEnding.rawValue
        ) {
            apply(edit)
            return
        }
        guard lineEnding != .lf else { return super.insertNewline(sender) }
        insertText(lineEnding.rawValue, replacementRange: selectedRange())
    }

    override func insertTab(_ sender: Any?) {
        if tableTab(backwards: false) { return }
        if let storage = textStorage,
           let edit = TypingBehavior.indent(in: storage.mutableString, selection: selectedRange(), outdent: false) {
            apply(edit)
            return
        }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if tableTab(backwards: true) { return }
        if let storage = textStorage,
           let edit = TypingBehavior.indent(in: storage.mutableString, selection: selectedRange(), outdent: true) {
            apply(edit)
            return
        }
        super.insertBacktab(sender)
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if let action = item.action, Self.formattingActions.contains(action) { return isEditable }
        // A plain-text view disables Paste when the pasteboard holds only an image; Hashline stores it.
        if item.action == #selector(paste(_:)), isEditable, ImageInsertion.hasImages(.general) { return true }
        if let action = item.action, Self.tableActions.contains(action) { return isEditable && isInTable }
        if item.action == #selector(performTextFinderAction(_:))
            || item.action == #selector(performFindPanelAction(_:)) {
            let replacing = Set([NSTextFinder.Action.replace, .replaceAndFind, .replaceAll, .replaceAllInSelection,
                                 .showReplaceInterface].map(\.rawValue))
            return onFindAction != nil && (isEditable || !replacing.contains(item.tag))
        }
        return super.validateUserInterfaceItem(item)
    }

    static let formattingActions: Set<Selector> = [
        #selector(toggleBold(_:)), #selector(toggleItalic(_:)), #selector(toggleUnderlineMarkup(_:)),
        #selector(toggleStrikethrough(_:)), #selector(toggleInlineCode(_:)), #selector(setParagraph(_:)),
        #selector(setHeading1(_:)), #selector(setHeading2(_:)), #selector(setHeading3(_:)),
        #selector(setHeading4(_:)), #selector(setHeading5(_:)), #selector(setHeading6(_:)),
        #selector(toggleBulletList(_:)), #selector(toggleNumberedList(_:)), #selector(toggleTaskList(_:)),
        #selector(toggleQuote(_:)), #selector(insertMarkdownLink(_:)), #selector(insertMarkdownImage(_:)),
        #selector(insertCodeBlock(_:)), #selector(insertTable(_:)), #selector(insertHorizontalRule(_:)),
        #selector(insertFootnote(_:)), #selector(insertMathBlock(_:)), #selector(insertTableOfContents(_:)),
        #selector(insertFrontMatter(_:)), #selector(copyAsMarkdown(_:)), #selector(copyAsHTML(_:)),
        #selector(copyAsPlainText(_:)), #selector(copyImagesToAssets(_:)), #selector(downloadRemoteImages(_:)),
    ]

    static let tableActions: Set<Selector> = [
        #selector(formatTable(_:)), #selector(insertRowAbove(_:)), #selector(insertRowBelow(_:)),
        #selector(deleteTableRow(_:)), #selector(insertColumnLeft(_:)), #selector(insertColumnRight(_:)),
        #selector(deleteTableColumn(_:)), #selector(alignColumnLeft(_:)), #selector(alignColumnCenter(_:)),
        #selector(alignColumnRight(_:)),
    ]
}
