import AppKit
import HashlineCore

// MARK: View modes (F5): text width, focus, typewriter, reading mode, status bar

extension EditorSession {

    /// Reading mode shows only the preview; keyboard focus moves with it, so keys never
    /// edit the hidden text. The editor keeps its caret and scroll position.
    func setReadingMode(_ reading: Bool) {
        preview?.setReading(reading)
        guard let scrollView = editorScrollView else { return }
        if reading {
            // Remember where the editor ended, to put the divider back afterwards.
            editorWidthBeforeReading = scrollView.frame.width
            return
        }
        guard let textView else { return }
        guard let window = textView.window else {
            textView.becomesFirstResponderInWindow = true
            return
        }
        window.makeFirstResponder(textView)
        // A re-added split item gets an arbitrary width; restore the previous layout.
        var view: NSView? = scrollView
        while let current = view, !(current.superview is NSSplitView) { view = current.superview }
        if let item = view, let split = item.superview as? NSSplitView,
           let index = split.arrangedSubviews.firstIndex(of: item), let width = editorWidthBeforeReading {
            let dividerIndex = index < split.arrangedSubviews.count - 1 ? index : index - 1
            let position = index < split.arrangedSubviews.count - 1 ? item.frame.minX + width : item.frame.maxX - width
            if dividerIndex >= 0 { split.setPosition(position, ofDividerAt: dividerIndex) }
        }
    }

    func refreshStatus() {
        status.update(text: document.textStorage.mutableString)
        selectionChanged()
    }

    /// Text width, focus and typewriter mode from View settings; cheap when nothing changed.
    func applyViewSettings() {
        guard let textView else { return }
        let defaults = UserDefaults.standard
        let width = defaults.object(forKey: ViewSettings.textWidthKey) == nil
            ? ViewSettings.defaultWidth : defaults.integer(forKey: ViewSettings.textWidthKey)
        let focus = defaults.bool(forKey: ViewSettings.focusModeKey)
        let typewriter = defaults.bool(forKey: ViewSettings.typewriterModeKey)
        let key = "\(width)|\(focus)|\(typewriter)"
        guard key != appliedViewSettings else { return }
        appliedViewSettings = key
        textView.maxLineCharacters = width
        focusDelegate.isEnabled = focus
        // Only while focus mode is on: the delegate replaces every layout fragment.
        textView.textLayoutManager?.delegate = focus ? focusDelegate : nil
        focusedRange = nil
        if let viewport = textView.textLayoutManager?.textViewportLayoutController.viewportRange {
            textView.textLayoutManager?.invalidateLayout(for: viewport)
        }
        if let scrollView = textView.enclosingScrollView {
            let half = typewriter ? scrollView.contentView.bounds.height / 2 : 0
            scrollView.automaticallyAdjustsContentInsets = !typewriter
            if typewriter { scrollView.contentInsets = NSEdgeInsets(top: half, left: 0, bottom: half, right: 0) }
        }
        selectionChanged()
    }

    func selectionChanged() {
        guard let textView, let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        if UserDefaults.standard.bool(forKey: ViewSettings.statusBarKey) {
            status.updateSelection(selection.length > 0 && selection.length < 500_000
                ? storage.mutableString.substring(with: selection) as NSString : nil)
        }
        if focusDelegate.isEnabled { updateFocus(caret: selection.location) }
        navigation.updateCaret(selection.location)
        if find.isVisible { find.updateCurrentIndex() }
        if UserDefaults.standard.bool(forKey: ViewSettings.typewriterModeKey) { centerCaret() }
    }

    /// Focus follows the Markdown block with the caret (a paragraph, a list, a code block…).
    fileprivate func updateFocus(caret: Int) {
        guard let textView, let layoutManager = textView.textLayoutManager,
              let contentStorage = textView.textContentStorage, let blockMap = highlighter?.blockMap else { return }
        var range = (textView.textStorage?.mutableString ?? "").paragraphRange(for: NSRange(location: caret, length: 0))
        if let index = blockMap.blockIndex(at: caret), NSLocationInRange(caret, blockMap.blocks[index].range)
            || NSMaxRange(blockMap.blocks[index].range) == caret {
            range = blockMap.blocks[index].range
        }
        if let frontMatter = FrontMatter.detect(in: textView.textStorage?.mutableString ?? ""),
           NSLocationInRange(caret, frontMatter.range) {
            range = frontMatter.range
        }
        guard range != focusedRange else { return }
        let previous = focusedRange
        focusedRange = range
        let start = contentStorage.documentRange.location
        func textRange(_ nsRange: NSRange) -> NSTextRange? {
            guard let lower = contentStorage.location(start, offsetBy: nsRange.location),
                  let upper = contentStorage.location(lower, offsetBy: nsRange.length) else { return nil }
            return NSTextRange(location: lower, end: upper)
        }
        focusDelegate.focused = textRange(range)
        for changed in [previous, range].compactMap({ $0 }) {
            if let changedRange = textRange(changed) { layoutManager.invalidateLayout(for: changedRange) }
        }
        if let viewport = layoutManager.textViewportLayoutController.viewportRange {
            layoutManager.invalidateLayout(for: viewport)
        }
    }

    /// Typewriter mode: the caret line stays in the vertical middle of the window.
    fileprivate func centerCaret() {
        guard let textView, let scrollView = textView.enclosingScrollView,
              let layoutManager = textView.textLayoutManager,
              let selection = layoutManager.textSelections.first?.textRanges.first else { return }
        var caretFrame = CGRect.zero
        layoutManager.enumerateTextSegments(in: selection, type: .selection, options: []) { _, frame, _, _ in
            caretFrame = frame
            return false
        }
        let caretY = caretFrame.midY + textView.textContainerOrigin.y
        let clip = scrollView.contentView
        let target = caretY - clip.bounds.height / 2
        guard abs(clip.bounds.origin.y - target) > 1 else { return }
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: target))
        scrollView.reflectScrolledClipView(clip)
    }
}

/// Hands TextKit 2 layout fragments that can draw dimmed (focus mode).
@MainActor
final class FocusDelegate: NSObject, NSTextLayoutManagerDelegate {
    var isEnabled = false
    /// The block the caret is in; everything else is drawn dimmed.
    nonisolated(unsafe) var focused: NSTextRange?

    nonisolated func textLayoutManager(_ textLayoutManager: NSTextLayoutManager,
                                       textLayoutFragmentFor location: any NSTextLocation,
                                       in textElement: NSTextElement) -> NSTextLayoutFragment {
        let fragment = FocusLayoutFragment(textElement: textElement, range: textElement.elementRange)
        let enabled = MainActor.assumeIsolated { isEnabled }
        if enabled {
            fragment.isDimmed = { [weak self] range in
                guard let focused = self?.focused else { return false }
                return !focused.intersects(range) && !(range.isEmpty && focused.contains(range.location))
            }
        }
        return fragment
    }
}
