import AppKit
import HashlineCore
import Observation

/// Find and replace in one document (⌘F, ⌥⌘F): literal text or a regular expression, whole words,
/// case. Replaces NSTextFinder's bar, which has no regex. Matches are found off the main thread
/// after each typing pause and highlighted with rendering attributes (the text is untouched).
@MainActor
@Observable
final class FindController {
    var isVisible = false
    var showsReplace = false
    var query = SearchQuery(text: "") {
        didSet { if query != oldValue { scheduleSearch(selectFirst: true) } }
    }
    var replacement = ""
    private(set) var matches: [NSRange] = []
    private(set) var currentIndex: Int?
    private(set) var errorMessage: String?
    /// Incremented to ask the bar to focus its search field.
    private(set) var focusRequest = 0

    @ObservationIgnored weak var textView: EditorTextView?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var isStale = true
    @ObservationIgnored private var highlighted = false

    nonisolated static let matchLimit = 10_000
    static let highlightLimit = 2_000

    var summary: String {
        if let errorMessage { return errorMessage }
        if query.text.isEmpty { return "" }
        if matches.isEmpty { return String(localized: "No results") }
        let total = matches.count >= Self.matchLimit ? "\(Self.matchLimit)+" : "\(matches.count)"
        return currentIndex.map { String(localized: "\($0 + 1) of \(total)") } ?? String(localized: "\(total) found")
    }

    // MARK: Commands (NSTextFinder actions from the Edit ▸ Find menu)

    func perform(_ action: NSTextFinder.Action) {
        let handlers: [NSTextFinder.Action: (FindController) -> Void] = [
            .showFindInterface: { $0.show(replace: false) },
            .showReplaceInterface: { $0.show(replace: true) },
            .hideFindInterface: { $0.close() },
            .hideReplaceInterface: { $0.showsReplace = false },
            .nextMatch: { $0.findNext(backwards: false) },
            .previousMatch: { $0.findNext(backwards: true) },
            .setSearchString: { $0.useSelection() },
            .replace: { $0.replaceCurrent(findNext: false) },
            .replaceAndFind: { $0.replaceCurrent(findNext: true) },
            .replaceAll: { $0.replaceAll() },
            .replaceAllInSelection: { $0.replaceAll() },
            .selectAll: { $0.selectAll() },
            .selectAllInSelection: { $0.selectAll() },
        ]
        handlers[action]?(self)
    }

    func show(replace: Bool) {
        if let textView, let storage = textView.textStorage, textView.selectedRange().length > 0,
           textView.selectedRange().length < 200 {
            let selected = storage.mutableString.substring(with: textView.selectedRange())
            if !selected.contains("\n") {
                query.text = query.isRegex ? NSRegularExpression.escapedPattern(for: selected) : selected
            }
        }
        isVisible = true
        if replace { showsReplace = true }
        focusRequest += 1
        if isStale { scheduleSearch(selectFirst: false) }
    }

    func close() {
        isVisible = false
        task?.cancel()
        clearHighlights()
        if let textView { textView.window?.makeFirstResponder(textView) }
    }

    func useSelection() {
        guard let textView, let storage = textView.textStorage, textView.selectedRange().length > 0 else { return }
        let selected = storage.mutableString.substring(with: textView.selectedRange())
        query.text = query.isRegex ? NSRegularExpression.escapedPattern(for: selected) : selected
    }

    func findNext(backwards: Bool) {
        guard let textView else { return }
        if isStale { searchNow() }
        let selection = textView.selectedRange()
        let from = backwards ? selection.location : NSMaxRange(selection)
        guard let match = TextSearch.next(in: matches, after: from, backwards: backwards) else {
            NSSound.beep()
            return
        }
        select(match)
    }

    func replaceCurrent(findNext next: Bool) {
        guard let textView, let storage = textView.textStorage else { return }
        if isStale { searchNow() }
        let selection = textView.selectedRange()
        guard matches.contains(selection) else { return findNext(backwards: false) }
        do {
            let text = try TextSearch.replacement(for: selection, in: storage.mutableString, query: query,
                                                  template: replacement)
            let caret = NSRange(location: selection.location + (text as NSString).length, length: 0)
            textView.apply(TextEdit(range: selection, replacement: text, selection: caret), actionName: "Replace")
            searchNow()
            if next { findNext(backwards: false) }
        } catch {
            errorMessage = String(localized: "Invalid pattern")
        }
    }

    func replaceAll() {
        guard let textView, let storage = textView.textStorage else { return }
        do {
            guard let result = try TextSearch.replaceAll(query, with: replacement, in: storage.mutableString) else {
                NSSound.beep()
                return
            }
            textView.apply(result.edit, actionName: "Replace All")
            searchNow()
            errorMessage = nil
            Performance.logger.notice("Replaced \(result.count) matches")
        } catch {
            errorMessage = String(localized: "Invalid pattern")
        }
    }

    func selectAll() {
        guard let textView else { return }
        if isStale { searchNow() }
        guard !matches.isEmpty else { return }
        textView.selectedRanges = matches.map { NSValue(range: $0) }
    }

    // MARK: Searching

    /// The text changed: matches are out of date until the next pause.
    func textDidChange() {
        isStale = true
        if isVisible { scheduleSearch(selectFirst: false) }
    }

    private func scheduleSearch(selectFirst: Bool) {
        task?.cancel()
        guard isVisible, let textView, let storage = textView.textStorage else { return }
        let text = UncheckedText(text: NSString(string: storage.mutableString as String))
        let query = query
        task = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[NSRange], Error> in
                Result { try TextSearch.matches(of: query, in: text.text, limit: Self.matchLimit) }
            }.value
            guard let self, !Task.isCancelled else { return }
            self.apply(result)
            if selectFirst, let textView = self.textView,
               let match = TextSearch.next(in: self.matches, after: textView.selectedRange().location) {
                self.select(match)
            }
        }
    }

    private func searchNow() {
        guard let textView, let storage = textView.textStorage else { return }
        task?.cancel()
        apply(Result { try TextSearch.matches(of: query, in: storage.mutableString, limit: Self.matchLimit) })
    }

    private func apply(_ result: Result<[NSRange], Error>) {
        isStale = false
        switch result {
        case .success(let found):
            matches = found
            errorMessage = nil
        case .failure:
            matches = []
            errorMessage = String(localized: "Invalid pattern")
        }
        updateCurrentIndex()
        highlight()
    }

    private func select(_ match: NSRange) {
        guard let textView else { return }
        textView.setSelectedRange(match)
        textView.scrollRangeToVisible(match)
        textView.showFindIndicator(for: match)
        updateCurrentIndex()
    }

    func updateCurrentIndex() {
        guard let selection = textView?.selectedRange() else { return }
        currentIndex = matches.firstIndex(of: selection)
    }

    // MARK: Highlights

    private func highlight() {
        clearHighlights()
        guard isVisible, let textView, let layoutManager = textView.textLayoutManager,
              let contentStorage = textView.textContentStorage else { return }
        let color = NSColor.findHighlightColor.withAlphaComponent(0.35)
        for range in matches.prefix(Self.highlightLimit) {
            if let textRange = contentStorage.textRange(for: range) {
                layoutManager.addRenderingAttribute(.backgroundColor, value: color, for: textRange)
            }
        }
        highlighted = !matches.isEmpty
    }

    private func clearHighlights() {
        guard highlighted, let textView, let layoutManager = textView.textLayoutManager else { return }
        layoutManager.removeRenderingAttribute(.backgroundColor, for: layoutManager.documentRange)
        highlighted = false
    }
}

extension NSTextContentStorage {
    /// TextKit 2 range for a UTF-16 range of the document.
    func textRange(for range: NSRange) -> NSTextRange? {
        guard let start = location(documentRange.location, offsetBy: range.location),
              let end = location(start, offsetBy: range.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }
}
