import AppKit
import Observation
import HashlineCore

/// Per-window editing state: highlighter, preview and the scroll link between them.
@MainActor
final class EditorSession {
    let document: MarkdownDocument
    private(set) var highlighter: SyntaxHighlighter?
    private(set) weak var textView: EditorTextView?
    private(set) var preview: PreviewController?
    private var isEditorEditable = false
    private var formatToolbar: FormatToolbar?
    let status = DocumentStatus()
    /// Observable for the window: the editor joined the window and became editable once.
    let readiness = EditorReadiness()
    let find = FindController()
    let navigation = DocumentNavigation()
    let conflict = DiskConflict()
    /// The assistant's conversation, created when its panel first shows (ADR 0019).
    private(set) lazy var assistant = makeAssistant()
    private var fileMonitor: FileChangeMonitor?
    /// The editor's scroll view, kept while reading mode removes it from the window.
    var editorScrollView: NSScrollView?
    let focusDelegate = FocusDelegate()
    var editorWidthBeforeReading: CGFloat?
    nonisolated(unsafe) var splitObserver: NSObjectProtocol?
    var isApplyingSplit = false
    var isSplitApplyScheduled = false
    var focusedRange: NSRange?
    nonisolated(unsafe) private var viewSettingsObserver: NSObjectProtocol?
    nonisolated(unsafe) private var themeObserver: NSObjectProtocol?
    var appliedViewSettings = ""
    /// The saved file; nil for an untitled document.
    var documentURL: URL? {
        didSet {
            preview?.documentURL = documentURL
            DocumentReveal.applyPending(to: self)
            if documentURL != oldValue {
                fileMonitor = documentURL.map { FileChangeMonitor(url: $0) { [weak self] in self?.checkDiskVersion() } }
            }
        }
    }
    private var isPreviewUpdateScheduled = false
    private var lastEdit = ContinuousClock.now
    // Written once in attach(), read in deinit (NotificationCenter removal is thread-safe).
    nonisolated(unsafe) private var scrollObserver: NSObjectProtocol?

    /// Characters styled synchronously on open; the rest is styled in the background.
    private static let initialStyledLength = 30_000
    /// Typing pauses shorter than this do not update the preview.
    private static let previewDelay: Duration = .milliseconds(60)

    init(document: MarkdownDocument) {
        self.document = document
        DocumentReveal.register(self)
        navigation.onNeedsUpdate = { [weak self] in self?.updateNavigation() }
    }

    deinit {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        if let viewSettingsObserver { NotificationCenter.default.removeObserver(viewSettingsObserver) }
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
        if let splitObserver { NotificationCenter.default.removeObserver(splitObserver) }
    }

    /// Called once the editor accepts input; starts the preview's WebKit.
    func editorBecameEditable() {
        isEditorEditable = true
        readiness.isEditable = true
        if let window = textView?.window { formatToolbar = FormatToolbar.install(in: window) }
        preview?.load()
        DocumentReveal.applyPending(to: self)
        DispatchQueue.main.async { [weak self] in self?.observeSplit() }
    }

    /// Inserts `text` into an empty, editable document; false otherwise.
    func fillIfEmpty(with text: String) -> Bool {
        guard isEditorEditable, let textView, document.textStorage.length == 0 else { return false }
        textView.insertText(text, replacementRange: NSRange(location: 0, length: 0))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        return true
    }

    /// Selects `range` and scrolls to it; false while the editor is not ready.
    @discardableResult
    func reveal(_ range: NSRange) -> Bool {
        guard isEditorEditable, let textView, let storage = textView.textStorage,
              NSMaxRange(range) <= storage.length else { return false }
        textView.window?.makeKeyAndOrderFront(nil)
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
        return true
    }

    /// Jumps to a heading from the outline, keeping it near the top of the view.
    func jump(to item: OutlineItem) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: item.range.location, length: 0))
        if let layoutManager = textView.textLayoutManager, let contentStorage = textView.textContentStorage,
           let textRange = contentStorage.textRange(for: NSRange(location: item.range.location, length: 0)) {
            layoutManager.ensureLayout(for: textRange)
            var frame = CGRect.zero
            layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, rect, _, _ in
                frame = rect
                return false
            }
            let clip = textView.enclosingScrollView?.contentView
            clip?.scroll(to: NSPoint(x: 0, y: max(frame.minY + textView.textContainerOrigin.y - 12, 0)))
            if let clip { textView.enclosingScrollView?.reflectScrolledClipView(clip) }
        } else {
            textView.scrollRangeToVisible(item.range)
        }
    }

    func updateNavigation() {
        guard let blocks = highlighter?.blockMap?.blocks, let textView else { return }
        navigation.update(blocks: blocks, text: document.textStorage.mutableString,
                          caret: textView.selectedRange().location)
    }

    func printPreview() {
        guard let window = textView?.window else { return }
        guard let webView = preview?.webView else { return NSSound.beep() }
        let info = NSPrintInfo.shared
        info.isVerticallyCentered = false
        let operation = webView.printOperation(with: info)
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func attach(_ textView: EditorTextView) {
        self.textView = textView
        let theme = EditorTheme.forAppearance(textView.effectiveAppearance)
        let highlighter = SyntaxHighlighter(storage: document.textStorage, theme: theme)
        highlighter.onBlocksChanged = { [weak self] in self?.schedulePreviewUpdate() }
        highlighter.onReady = { [weak self, weak highlighter] in
            // SwiftUI may have created the preview before the editor; fill it now.
            if let highlighter, let blocks = highlighter.blockMap?.blocks {
                self?.preview?.update(blocks: blocks, text: highlighter.storage.mutableString)
            }
        }
        self.highlighter = highlighter
        apply(theme, to: textView)
        highlighter.load(priority: NSRange(location: 0, length: Self.initialStyledLength))

        textView.onAppearanceChange = { [weak self] in self?.updateTheme() }
        themeObserver = NotificationCenter.default.addObserver(
            forName: .hashlineThemeChanged, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.updateTheme() } }
        textView.onWindowAvailable = { window in
            FormatToolbar.installPlaceholder(in: window)
        }
        textView.linkAtOffset = { [weak self] offset in self?.link(at: offset) }
        textView.onSelectionChange = { [weak self] in self?.selectionChanged() }
        textView.onFindAction = { [weak self] action in self?.find.perform(action) }
        find.textView = textView
        applyViewSettings()
        viewSettingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.applyViewSettings() } }
        status.update(text: document.textStorage.mutableString)
        textView.onSelectionCaptureNeeded = { [weak self] replaced in
            self?.highlighter?.pendingReplacedText = replaced
        }

        if let clipView = textView.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clipView, queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncPreviewScroll() }
            }
        }
    }

    /// The preview is created on first request, so a hidden preview never loads WebKit.
    /// WebKit itself starts only after the editor is editable.
    func previewController() -> PreviewController {
        if let preview { return preview }
        let controller = PreviewController()
        controller.documentURL = documentURL
        controller.onTaskToggle = { [weak self] blockID, index in self?.toggleTask(blockID: blockID, index: index) }
        preview = controller
        if isEditorEditable { controller.load() }
        if let highlighter, let blocks = highlighter.blockMap?.blocks {
            controller.update(blocks: blocks, text: highlighter.storage.mutableString)
        }
        return controller
    }

    // MARK: Tasks and links

    private func toggleTask(blockID: String, index: Int) {
        guard let textView, let highlighter, let blockMap = highlighter.blockMap,
              let block = blockMap.blocks.first(where: { $0.id == blockID }),
              let edit = block.toggleTask(at: index, in: highlighter.storage.mutableString) else { return }
        textView.breakUndoCoalescing()
        textView.apply(edit, actionName: "Toggle Task")
    }

    private func link(at offset: Int) -> String? {
        guard let highlighter, let blockMap = highlighter.blockMap,
              let index = blockMap.blockIndex(at: offset) else { return nil }
        return blockMap.blocks[index].link(at: offset, in: highlighter.storage.mutableString)
    }

    /// Appearance, theme or font changed: restyle from the existing parse (no reparsing).
    private func updateTheme() {
        guard let textView else { return }
        let theme = EditorTheme.forAppearance(textView.effectiveAppearance)
        guard theme !== highlighter?.theme else { return }
        ModeSwitchMetrics.measure("theme") {
            highlighter?.restyleAll(theme: theme, priority: visibleCharacterRange(of: textView))
            apply(theme, to: textView)
        }
    }

    private func apply(_ theme: EditorTheme, to textView: NSTextView) {
        textView.backgroundColor = theme.backgroundColor
        textView.insertionPointColor = theme.caretColor
        textView.selectedTextAttributes = theme.selectionAttributes
        textView.typingAttributes = theme.baseAttributes
        (textView as? EditorTextView)?.updateTextInsets()
        textView.enclosingScrollView?.backgroundColor = theme.backgroundColor
    }

    /// Runs after a typing pause (trailing debounce): full link-definition check, then the preview patch.
    private func schedulePreviewUpdate() {
        lastEdit = .now
        preview?.lastEdit = lastEdit
        guard !isPreviewUpdateScheduled else { return }
        isPreviewUpdateScheduled = true
        Task { @MainActor [weak self] in
            while let self, ContinuousClock.now - self.lastEdit < Self.previewDelay {
                try? await Task.sleep(for: Self.previewDelay - (ContinuousClock.now - self.lastEdit))
            }
            guard let self, let highlighter = self.highlighter else { return }
            self.isPreviewUpdateScheduled = false
            guard let blockMap = highlighter.blockMap else { return }
            if blockMap.validateDefinitions(in: highlighter.storage.mutableString), let textView {
                highlighter.restyleAll(priority: self.visibleCharacterRange(of: textView))
            }
            self.preview?.update(blocks: blockMap.blocks, text: highlighter.storage.mutableString)
            if UserDefaults.standard.bool(forKey: ViewSettings.statusBarKey) {
                self.status.update(text: highlighter.storage.mutableString)
            }
            self.find.textDidChange()
            self.updateNavigation()
            self.syncPreviewScroll()
        }
    }

    // MARK: Scroll sync (editor → preview)

    private func syncPreviewScroll() {
        guard let preview, let textView, let blockMap = highlighter?.blockMap else { return }
        let visible = textView.visibleRect
        if visible.maxY >= textView.bounds.maxY - 1, visible.minY > 0 {
            preview.scrollToBottom()
            return
        }
        guard let (offset, fraction) = topVisibleCharacter(of: textView),
              let index = blockMap.blockIndex(at: offset) else { return }
        let block = blockMap.blocks[index]
        let position = Double(offset - block.range.location) + fraction
        preview.scroll(toBlock: block.id, fraction: max(0, min(1, position / Double(max(block.range.length, 1)))))
    }

    /// Character offset of the first visible line fragment and how far (0…1 of a line) it is scrolled past.
    private func topVisibleCharacter(of textView: NSTextView) -> (Int, Double)? {
        guard let layoutManager = textView.textLayoutManager,
              let contentStorage = textView.textContentStorage else { return nil }
        let point = CGPoint(x: 0, y: max(textView.visibleRect.minY - textView.textContainerOrigin.y, 0))
        guard let fragment = layoutManager.textLayoutFragment(for: point) else { return nil }
        let offset = contentStorage.offset(from: contentStorage.documentRange.location,
                                           to: fragment.rangeInElement.location)
        let frame = fragment.layoutFragmentFrame
        let fraction = frame.height > 0 ? Double((point.y - frame.minY) / frame.height) : 0
        let length = contentStorage.offset(from: fragment.rangeInElement.location,
                                           to: fragment.rangeInElement.endLocation)
        return (offset, fraction * Double(length))
    }

    /// The laid-out viewport plus a margin for the first scroll; restyles of the rest run in the
    /// background (a fixed 30 000 characters cost ~60 ms on a theme switch).
    private func visibleCharacterRange(of textView: NSTextView) -> NSRange {
        if let layoutManager = textView.textLayoutManager, let contentStorage = textView.textContentStorage,
           let viewport = layoutManager.textViewportLayoutController.viewportRange {
            let start = contentStorage.offset(from: contentStorage.documentRange.location, to: viewport.location)
            let length = contentStorage.offset(from: viewport.location, to: viewport.endLocation)
            let margin = 2_000
            return NSRange(location: max(start - margin, 0), length: length + 2 * margin)
        }
        guard let (offset, _) = topVisibleCharacter(of: textView) else {
            return NSRange(location: 0, length: Self.initialStyledLength)
        }
        return NSRange(location: offset, length: Self.initialStyledLength)
    }
}

/// Whether the editor has been editable at least once. The preview and the toolbar start from that
/// moment, so reading mode may hide the editor only afterwards (a window opened in reading mode
/// would otherwise stay empty).
@MainActor
@Observable
final class EditorReadiness {
    var isEditable = false
}
