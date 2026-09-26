import AppKit

enum SplitSettings {
    /// The editor's share of the editor + preview width, set by dragging the divider.
    static let editorFractionKey = "editorSplitFraction"
    /// The library's width in points, set by dragging its divider.
    static let libraryWidthKey = "librarySplitWidth"
    static let libraryWidths: ClosedRange<CGFloat> = 220...380
    static let editorMinWidth: CGFloat = 320
    static let previewMinWidth: CGFloat = 280
}

// MARK: Dividers (library | editor | preview | assistant), remembered across windows, documents and launches

extension EditorSession {

    /// The window's split view and which of its items are visible.
    private struct SplitLayout {
        let split: NSSplitView
        let library: NSView?
        let editor: NSView?
        let preview: NSView?
        let assistant: NSView?
    }

    /// The split view item holding `view`.
    private func splitItem(containing view: NSView?) -> NSView? {
        var current = view
        while let item = current, !(item.superview is NSSplitView) { current = item.superview }
        return current
    }

    private func splitLayout() -> SplitLayout? {
        let editorView = editorScrollView?.window == nil ? nil : editorScrollView
        let previewView = preview?.containerView.window == nil ? nil : preview?.containerView
        let editor = splitItem(containing: editorView)
        let preview = splitItem(containing: previewView)
        guard let split = (editor ?? preview)?.superview as? NSSplitView else { return nil }
        // The library is always the first item; it is neither the editor nor the preview.
        let first = split.arrangedSubviews.first
        let library = first === editor || first === preview ? nil : first
        // The assistant is always the last item when it shows.
        let last = split.arrangedSubviews.last
        let assistant = last === editor || last === preview || last === library ? nil : last
        return SplitLayout(split: split, library: library, editor: editor, preview: preview, assistant: assistant)
    }

    /// A drag of a divider saves the layout; any other resize (window, library, the preview or
    /// the editor coming back, SwiftUI's own layout) puts the dividers back to it.
    func observeSplit() {
        guard splitObserver == nil else { return }
        splitObserver = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let dividerIndex = notification.userInfo?["NSSplitViewDividerIndex"] as? Int
            let split = notification.object as? NSSplitView
            MainActor.assumeIsolated { self?.splitDidResize(split, draggedDivider: dividerIndex) }
        }
        applySplitLayout()
    }

    private func splitDidResize(_ split: NSSplitView?, draggedDivider: Int?) {
        guard !isApplyingSplit, let layout = splitLayout(), layout.split === split else { return }
        // Only the user's mouse drag changes the saved layout. SwiftUI also moves dividers
        // (with an index) when items appear, which must not overwrite it. The split view itself
        // is in live resize while its divider is dragged; only the window's live resize is excluded.
        let isUserDrag = draggedDivider != nil && layout.split.window?.inLiveResize != true
            && NSApp.currentEvent?.type == .leftMouseDragged
        guard isUserDrag, let draggedDivider else { return scheduleSplitLayout() }
        let items = layout.split.arrangedSubviews
        let defaults = UserDefaults.standard
        if let library = layout.library, items.firstIndex(of: library) == draggedDivider {
            defaults.set(Double(library.frame.width), forKey: SplitSettings.libraryWidthKey)
            // The editor absorbed the change; keep the editor/preview ratio.
            scheduleSplitLayout()
        } else if let assistant = layout.assistant, let index = items.firstIndex(of: assistant),
                  index - 1 == draggedDivider {
            defaults.set(Double(assistant.frame.width), forKey: AssistantSettings.panelWidthKey)
            scheduleSplitLayout()
        } else if let editor = layout.editor, let preview = layout.preview,
                  items.firstIndex(of: editor) == draggedDivider {
            let total = editor.frame.width + preview.frame.width
            guard total > 0 else { return }
            defaults.set(Double(editor.frame.width / total), forKey: SplitSettings.editorFractionKey)
        }
    }

    /// Once per run-loop turn: live window resizing posts many notifications.
    func scheduleSplitLayout() {
        guard !isSplitApplyScheduled else { return }
        isSplitApplyScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.isSplitApplyScheduled = false
            self?.applySplitLayout()
        }
    }

    /// Moves the dividers to the saved library width and editor/preview ratio; true when the
    /// editor/preview divider was placed from a saved ratio.
    @discardableResult
    func applySplitLayout() -> Bool {
        guard let layout = splitLayout() else { return false }
        let defaults = UserDefaults.standard
        let items = layout.split.arrangedSubviews
        isApplyingSplit = true
        defer { isApplyingSplit = false }
        if let library = layout.library, let index = items.firstIndex(of: library),
           defaults.object(forKey: SplitSettings.libraryWidthKey) != nil {
            let bounds = SplitSettings.libraryWidths
            let width = min(max(defaults.double(forKey: SplitSettings.libraryWidthKey), bounds.lowerBound),
                            bounds.upperBound)
            let target = library.frame.minX + width.rounded()
            if abs(library.frame.maxX - target) > 1 { layout.split.setPosition(target, ofDividerAt: index) }
        }
        if let assistant = layout.assistant, let index = items.firstIndex(of: assistant), index > 0 {
            // SwiftUI would give the panel an equal share; until a drag saves a width it gets the default.
            let bounds = AssistantSettings.panelWidths
            let saved = defaults.object(forKey: AssistantSettings.panelWidthKey) == nil
                ? AssistantSettings.defaultPanelWidth : defaults.double(forKey: AssistantSettings.panelWidthKey)
            let width = min(max(saved, bounds.lowerBound), bounds.upperBound).rounded()
            let target = assistant.frame.maxX - width - layout.split.dividerThickness
            if abs(assistant.frame.minX - layout.split.dividerThickness - target) > 1 {
                layout.split.setPosition(target, ofDividerAt: index - 1)
            }
        }
        guard let editor = layout.editor, let preview = layout.preview, let index = items.firstIndex(of: editor),
              defaults.object(forKey: SplitSettings.editorFractionKey) != nil else { return false }
        let fraction = min(max(defaults.double(forKey: SplitSettings.editorFractionKey), 0.1), 0.9)
        let total = editor.frame.width + preview.frame.width
        guard total > 0 else { return false }
        // Within the minimum widths: a divider pushed past them would move the library's too.
        let editorWidth = min(max((total * fraction).rounded(), SplitSettings.editorMinWidth),
                              total - SplitSettings.previewMinWidth)
        let target = editor.frame.minX + editorWidth
        if abs(editor.frame.maxX - target) > 1 { layout.split.setPosition(target, ofDividerAt: index) }
        return true
    }
}
