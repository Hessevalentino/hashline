import AppKit
import HashlineCore
import Observation
import SwiftUI

/// View settings (View menu). Stored in user defaults so every window follows them.
enum ViewSettings {
    static let textWidthKey = "textWidth"
    static let focusModeKey = "focusMode"
    static let typewriterModeKey = "typewriterMode"
    static let statusBarKey = "showsStatusBar"
    static let readingModeKey = "readingMode"

    /// Maximum line length in characters; 0 = full width.
    static let widths: [(label: LocalizedStringResource, characters: Int)] = [
        ("Narrow (72 characters)", 72), ("Medium (88 characters)", 88), ("Wide (110 characters)", 110),
        ("Full Width", 0),
    ]
    static let defaultWidth = 88
}

/// Words, characters and lines for the status bar; recomputed off the main thread after edits.
@MainActor
@Observable
final class DocumentStatus {
    var document = TextStatistics.of("")
    var selection: TextStatistics?
    @ObservationIgnored private var task: Task<Void, Never>?

    func update(text: NSString) {
        task?.cancel()
        let copy = NSString(string: text as String)  // immutable snapshot for the other thread
        let box = UncheckedText(text: copy)
        task = Task { @MainActor [weak self] in
            let statistics = await Task.detached(priority: .utility) { TextStatistics.of(box.text) }.value
            guard !Task.isCancelled else { return }
            self?.document = statistics
        }
    }

    func updateSelection(_ text: NSString?) {
        selection = text.map { TextStatistics.of($0) }
    }
}

/// An immutable string copy handed to another thread.
struct UncheckedText: @unchecked Sendable {
    let text: NSString
}

/// Measures a view-mode switch: action → next frame committed.
@MainActor
enum ModeSwitchMetrics {
    static func measure(_ name: String, _ change: () -> Void) {
        let started = ContinuousClock.now
        change()
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false,
                                                          CFIndex.max) { _, _ in
            let elapsed = (ContinuousClock.now - started).milliseconds
            Performance.logger.notice(
                "Mode switch \(name, privacy: .public): \(elapsed, format: .fixed(precision: 1)) ms")
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}

// MARK: - Focus mode

/// Draws paragraphs outside the focused range dimmed. Used as every layout fragment while
/// focus mode is on; the text and its attributes stay untouched.
final class FocusLayoutFragment: NSTextLayoutFragment {
    /// Set by the editor; nil means focus mode is off.
    nonisolated(unsafe) var isDimmed: (@Sendable (NSTextRange) -> Bool)?

    override func draw(at point: CGPoint, in context: CGContext) {
        guard let isDimmed, isDimmed(rangeInElement) else { return super.draw(at: point, in: context) }
        context.saveGState()
        context.setAlpha(0.28)
        super.draw(at: point, in: context)
        context.restoreGState()
    }
}
