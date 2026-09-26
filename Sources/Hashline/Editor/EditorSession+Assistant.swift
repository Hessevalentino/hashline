import AppKit
import HashlineCore

extension EditorSession {
    /// The assistant reads and changes only this session's document.
    func makeAssistant() -> AssistantSession {
        AssistantSession(document: AssistantDocumentBridge(session: self))
    }
}

/// Why a tool call changed nothing; the message goes back to the model.
struct EditRefusal: Error {
    let message: String
}

/// The assistant's hands on one document (ADR 0019): its text and selection, the lock while the
/// assistant works, its edits as one undo step per instruction and the highlight of what changed.
@MainActor
final class AssistantDocumentBridge {
    private weak var session: EditorSession?
    /// Changed ranges of the last instruction, in the current text.
    private var highlights: [NSRange] = []
    private var isGroupOpen = false
    private var groupedByEvent = true
    private var wasEditable = true
    private var isApplying = false
    nonisolated(unsafe) private var textObserver: NSObjectProtocol?

    init(session: EditorSession) {
        self.session = session
    }

    deinit {
        if let textObserver { NotificationCenter.default.removeObserver(textObserver) }
    }

    private var textView: EditorTextView? { session?.textView }

    var text: String { session?.document.textStorage.string ?? "" }

    var selection: String? {
        guard let textView, let storage = textView.textStorage,
              let range = textView.selectedRanges.first?.rangeValue, range.length > 0,
              NSMaxRange(range) <= storage.length else { return nil }
        return storage.attributedSubstring(from: range).string
    }

    /// Read-only while the assistant works; the previous highlight goes away.
    func lock() {
        clearHighlights()
        guard let textView else { return }
        wasEditable = textView.isEditable
        textView.isEditable = false
    }

    /// Applies one tool call; the result goes back to the model.
    func apply(tool name: String, input: JSONValue) -> Result<Void, EditRefusal> {
        guard let textView, let storage = textView.textStorage else {
            return .failure(EditRefusal(message: "The document is closed; nothing was changed."))
        }
        switch DocumentEditTools.edit(for: name, input: input, in: storage.mutableString) {
        case .failure(let failure):
            return .failure(EditRefusal(message: failure.message))
        case .success(let edit):
            openUndoGroup()
            isApplying = true
            textView.isEditable = true
            textView.apply(edit)
            textView.isEditable = false
            isApplying = false
            record(edit)
            return .success(())
        }
    }

    /// Ends the instruction: one undo step, editable again, the changes highlighted until the next edit.
    func unlock() -> Int {
        let count = highlights.count
        if isGroupOpen, let undoManager = textView?.undoManager {
            undoManager.setActionName(String(localized: "Assistant Edit"))
            undoManager.endUndoGrouping()
            undoManager.groupsByEvent = groupedByEvent
            textView?.breakUndoCoalescing()
            isGroupOpen = false
        }
        textView?.isEditable = wasEditable
        showHighlights()
        return count
    }

    /// Selects and shows the first change of the last instruction.
    func revealChanges() {
        guard let first = highlights.first else { return }
        session?.reveal(first)
    }

    // MARK: Undo

    /// The instruction's edits arrive over several run-loop turns; automatic grouping would make each
    /// its own undo step, so one group stays open manually until `unlock`.
    private func openUndoGroup() {
        guard !isGroupOpen, let textView, let undoManager = textView.undoManager else { return }
        textView.breakUndoCoalescing()
        groupedByEvent = undoManager.groupsByEvent
        // An automatic group of the current event would otherwise enclose ours and never close.
        if undoManager.groupingLevel > 0, groupedByEvent { undoManager.endUndoGrouping() }
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        isGroupOpen = true
    }

    // MARK: Highlights

    /// Keeps earlier ranges in step with the text after `edit`.
    private func record(_ edit: TextEdit) {
        let delta = (edit.replacement as NSString).length - edit.range.length
        highlights = highlights.compactMap { range in
            if NSMaxRange(range) <= edit.range.location { return range }
            if range.location >= NSMaxRange(edit.range) {
                return NSRange(location: range.location + delta, length: range.length)
            }
            return nil
        }
        if edit.selection.length > 0 { highlights.append(edit.selection) }
    }

    private func showHighlights() {
        guard let textView, let layoutManager = textView.textLayoutManager,
              let contentStorage = textView.textContentStorage, !highlights.isEmpty else { return }
        let color = NSColor.controlAccentColor.withAlphaComponent(0.2)
        for range in highlights {
            if let textRange = contentStorage.textRange(for: range) {
                layoutManager.addRenderingAttribute(.backgroundColor, value: color, for: textRange)
            }
        }
        // The first edit by the user ends the highlight.
        textObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification, object: textView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isApplying else { return }
                // The user's edit may have moved the ranges: clear the whole text (find redraws its own).
                if let layoutManager = self.textView?.textLayoutManager {
                    layoutManager.removeRenderingAttribute(.backgroundColor, for: layoutManager.documentRange)
                }
                self.highlights = []
                self.clearHighlights()
            }
        }
    }

    func clearHighlights() {
        if let textObserver { NotificationCenter.default.removeObserver(textObserver) }
        textObserver = nil
        defer { highlights = [] }
        guard let textView, let layoutManager = textView.textLayoutManager,
              let contentStorage = textView.textContentStorage else { return }
        let length = textView.textStorage?.length ?? 0
        for range in highlights where NSMaxRange(range) <= length {
            if let textRange = contentStorage.textRange(for: range) {
                layoutManager.removeRenderingAttribute(.backgroundColor, for: textRange)
            }
        }
    }
}
