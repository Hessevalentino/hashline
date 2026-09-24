import AppKit
import HashlineCore
import Observation

/// Per-document outline for the sidebar: headings and the one the caret is under.
@MainActor
@Observable
final class DocumentNavigation {
    private(set) var outline: [OutlineItem] = []
    private(set) var currentIndex: Int?
    /// The outline is only computed while the sidebar shows it.
    @ObservationIgnored var isOutlineVisible = false {
        didSet { if isOutlineVisible && !oldValue { onNeedsUpdate?() } }
    }
    @ObservationIgnored var onNeedsUpdate: (() -> Void)?

    func update(blocks: [MarkdownBlock], text: NSString, caret: Int) {
        guard isOutlineVisible else { return }
        let items = DocumentOutline.items(in: blocks, text: text)
        if items != outline { outline = items }
        updateCaret(caret)
    }

    func updateCaret(_ caret: Int) {
        guard isOutlineVisible else { return }
        let index = DocumentOutline.currentIndex(in: outline, offset: caret)
        if index != currentIndex { currentIndex = index }
    }
}

/// Selecting a range in a document that may still be opening (search results, Quick Open).
@MainActor
enum DocumentReveal {
    private static var pending: [URL: NSRange] = [:]
    private static let sessions = NSHashTable<EditorSession>.weakObjects()

    static func register(_ session: EditorSession) {
        sessions.add(session)
    }

    /// Opens the document (as a tab of `window`) and selects `range` once it is editable.
    static func open(_ url: URL, range: NSRange?, besides window: NSWindow?) {
        let url = url.standardizedFileURL
        if let range {
            if let session = session(for: url), session.reveal(range) {
                // Already open: just bring it forward.
            } else {
                pending[url] = range
            }
        }
        LibraryStore.shared.openDocument(at: url, besides: window)
    }

    private static var pendingUntitledText: String?

    /// A new untitled window whose text is `text` (Services). The text is typed in as one undoable
    /// edit, so the document is marked edited and autosaves like any other.
    static func openUntitled(containing text: String) {
        pendingUntitledText = text
        do {
            try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
            NSApp.activate()
        } catch {
            pendingUntitledText = nil
            NSAlert(error: error).runModal()
        }
    }

    /// Called when a session learns its URL or becomes editable.
    static func applyPending(to session: EditorSession) {
        if let text = pendingUntitledText, session.documentURL == nil, session.fillIfEmpty(with: text) {
            pendingUntitledText = nil
        }
        guard let url = session.documentURL?.standardizedFileURL, let range = pending[url] else { return }
        if session.reveal(range) { pending[url] = nil }
    }

    static func session(for window: NSWindow) -> EditorSession? {
        sessions.allObjects.first { $0.textView?.window === window }
    }

    private static func session(for url: URL) -> EditorSession? {
        sessions.allObjects.first { $0.documentURL?.standardizedFileURL == url }
    }
}
