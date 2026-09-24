import AppKit

enum SplitSettings {
    /// The editor's share of the editor + preview width, set by dragging the divider.
    static let editorFractionKey = "editorSplitFraction"
}

// MARK: Divider between the editor and the preview, remembered across windows and launches

extension EditorSession {

    /// The split view with the editor item and the preview item right after it.
    private struct EditorSplit {
        let split: NSSplitView
        let index: Int
        let editor: NSView
        let preview: NSView
    }

    private func editorSplit() -> EditorSplit? {
        var view: NSView? = editorScrollView
        while let current = view, !(current.superview is NSSplitView) { view = current.superview }
        guard let item = view, let split = item.superview as? NSSplitView,
              let index = split.arrangedSubviews.firstIndex(of: item),
              index + 1 < split.arrangedSubviews.count else { return nil }
        return EditorSplit(split: split, index: index, editor: item, preview: split.arrangedSubviews[index + 1])
    }

    /// A drag of the editor/preview divider saves the ratio; any other resize (window, library,
    /// the preview or the editor coming back) puts the divider back to it.
    func observeSplit() {
        guard splitObserver == nil else { return }
        splitObserver = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let dividerIndex = notification.userInfo?["NSSplitViewDividerIndex"] as? Int
            let split = notification.object as? NSSplitView
            MainActor.assumeIsolated { self?.splitDidResize(split, draggedDivider: dividerIndex) }
        }
        applySplitFraction()
    }

    private func splitDidResize(_ split: NSSplitView?, draggedDivider: Int?) {
        guard !isApplyingSplit, let current = editorSplit(), current.split === split else { return }
        if draggedDivider == current.index {
            let total = current.editor.frame.width + current.preview.frame.width
            guard total > 0 else { return }
            UserDefaults.standard.set(Double(current.editor.frame.width / total),
                                      forKey: SplitSettings.editorFractionKey)
            return
        }
        scheduleSplitFraction()
    }

    /// Once per run-loop turn: live window resizing posts many notifications.
    func scheduleSplitFraction() {
        guard !isSplitApplyScheduled else { return }
        isSplitApplyScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.isSplitApplyScheduled = false
            self?.applySplitFraction()
        }
    }

    /// Moves the divider to the saved ratio; false without a saved ratio or a visible preview.
    @discardableResult
    func applySplitFraction() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: SplitSettings.editorFractionKey) != nil,
              let current = editorSplit() else { return false }
        let fraction = min(max(defaults.double(forKey: SplitSettings.editorFractionKey), 0.1), 0.9)
        let total = current.editor.frame.width + current.preview.frame.width
        guard total > 0 else { return false }
        let target = current.editor.frame.minX + (total * fraction).rounded()
        guard abs(current.editor.frame.maxX - target) > 1 else { return true }
        isApplyingSplit = true
        current.split.setPosition(target, ofDividerAt: current.index)
        isApplyingSplit = false
        return true
    }
}
