import AppKit
import HashlineCore

/// Keeps the block map in sync with the text storage and colours the source.
/// Only attributes change; the characters are never touched.
@MainActor
final class SyntaxHighlighter: NSObject, NSTextStorageDelegate {
    let storage: NSTextStorage
    /// Nil while a large document is being parsed in the background.
    private(set) var blockMap: BlockMap?
    /// Called once the block map exists (immediately for small documents).
    var onReady: (() -> Void)?
    private var editsSinceParseStarted = 0
    /// The background pass also resets base attributes (after a theme change).
    private var resetsInBackground = false
    private(set) var theme: EditorTheme
    /// Called after the block map changed (typing, undo, paste).
    var onBlocksChanged: (() -> Void)?
    /// Text about to be replaced, captured by the text view before the edit.
    /// Used only to notice deleted link reference definitions.
    var pendingReplacedText = ""

    /// Offset from which blocks still await background styling, if any.
    private var backgroundOffset: Int?
    private var backgroundStats = (started: ContinuousClock.now, chunks: 0, longest: Duration.zero)
    private var isStylingScheduled = false
    private var fontCache: [FontKey: NSFont] = [:]
    /// Code blocks (by block id) with a highlight request in flight.
    var pendingCode: Set<String> = []
    /// Edits this close to the start may create, change or remove front matter.
    static let frontMatterWindow = 20_000
    /// End of the front matter, 0 when there is none.
    var frontMatterEnd = 0

    private struct FontKey: Hashable {
        let traits: UInt32
        let size: CGFloat
    }

    /// Documents up to this length are parsed synchronously, so they never show unstyled text.
    private static let synchronousParseLimit = 100_000

    init(storage: NSTextStorage, theme: EditorTheme) {
        self.storage = storage
        self.theme = theme
        super.init()
        storage.delegate = self
    }

    /// Builds the block map and styles `priority` first. Large documents are parsed off the main
    /// thread; the text stays editable meanwhile and is styled when the parse lands.
    func load(priority: NSRange) {
        storage.setAttributes(theme.baseAttributes, range: NSRange(location: 0, length: storage.length))
        guard storage.length > Self.synchronousParseLimit else {
            let signpost = Performance.signposter.beginInterval("Parse")
            blockMap = BlockMap(text: storage.string)
            Performance.signposter.endInterval("Parse", signpost)
            restyleAll(priority: priority)
            onReady?()
            return
        }
        parseInBackground(priority: priority)
    }

    private func parseInBackground(priority: NSRange) {
        let text = storage.string
        editsSinceParseStarted = 0
        Task { @MainActor [weak self] in
            let box = await Task.detached(priority: .userInitiated) {
                let signpost = Performance.signposter.beginInterval("Parse")
                defer { Performance.signposter.endInterval("Parse", signpost) }
                return ParsedBlockMap(map: BlockMap(text: text))
            }.value
            guard let self else { return }
            // Typing during the parse invalidates the result; parse the current text again.
            guard self.editsSinceParseStarted == 0 else { return self.parseInBackground(priority: priority) }
            self.blockMap = box.map
            self.restyleAll(priority: priority)
            self.onReady?()
        }
    }

    /// Restyles the whole document: `priority` synchronously, the rest in the background.
    func restyleAll(theme: EditorTheme? = nil, priority: NSRange) {
        if let theme, theme !== self.theme {
            self.theme = theme
            fontCache = [:]
        }
        pendingCode = []
        guard blockMap != nil else { return }
        let signpost = Performance.signposter.beginInterval("Highlight")
        let text: NSString = storage.mutableString
        // Only the visible part now (resetting 1 MB of attributes took ~350 ms); the background
        // pass resets and restyles the rest block by block, gaps included.
        let whole = NSRange(location: 0, length: text.length)
        var visible = NSIntersectionRange(text.paragraphRange(for: NSIntersectionRange(priority, whole)), whole)
        if let blockMap, let first = blockMap.blockIndex(at: visible.location) {
            visible = NSUnionRange(visible, blockMap.blocks[first].range)
        }
        storage.beginEditing()
        storage.setAttributes(self.theme.baseAttributes, range: visible)
        styleFrontMatter(in: text)
        style(blocksIntersecting: visible)
        storage.endEditing()
        Performance.signposter.endInterval("Highlight", signpost)
        backgroundOffset = 0
        resetsInBackground = true
        backgroundStats = (.now, 0, .zero)
        scheduleBackgroundStyling()
    }

    // MARK: NSTextStorageDelegate

    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                 range editedRange: NSRange, changeInLength delta: Int) {
        // The storage is only edited on the main thread (text view, undo, document load).
        MainActor.assumeIsolated {
            guard editedMask.contains(.editedCharacters) else { return }
            handleEdit(editedRange: editedRange, delta: delta)
        }
    }

    private func handleEdit(editedRange: NSRange, delta: Int) {
        guard let blockMap else {
            editsSinceParseStarted += 1
            return
        }
        let signpost = Performance.signposter.beginInterval("Highlight")
        let started = ContinuousClock.now
        defer {
            Performance.signposter.endInterval("Highlight", signpost)
            TypingLatency.highlightSamples.append((ContinuousClock.now - started).milliseconds)
        }

        // mutableString avoids copying the whole document into a Swift String on every keystroke.
        let text: NSString = storage.mutableString
        blockMap.applyEdit(editedRange: editedRange, delta: delta, replacedText: pendingReplacedText, in: text)
        let replaced = blockMap.lastChangedBlocks
        pendingReplacedText = ""
        if let offset = backgroundOffset, editedRange.location < offset {
            backgroundOffset = max(offset + delta, editedRange.location)
        }

        // Reset the whole reparsed area: blocks may have shrunk or turned into plain text.
        var reset = text.paragraphRange(for: editedRange)
        for index in replaced {
            reset = NSUnionRange(reset, blockMap.blocks[index].range)
        }
        reset = NSIntersectionRange(reset, NSRange(location: 0, length: text.length))
        // Changing attributes (not characters) is allowed in didProcessEditing.
        storage.setAttributes(theme.baseAttributes, range: reset)
        if reset.location < Self.frontMatterWindow {
            let previousEnd = frontMatterEnd
            styleFrontMatter(in: text)
            // Front matter appeared or disappeared: the blocks it covers need restyling.
            if frontMatterEnd < previousEnd {
                let uncovered = NSRange(location: frontMatterEnd, length: previousEnd - frontMatterEnd + max(delta, 0))
                storage.setAttributes(theme.baseAttributes, range: NSIntersectionRange(uncovered,
                                      NSRange(location: 0, length: text.length)))
                style(blocksIntersecting: uncovered)
            }
        }
        for index in replaced {
            styleBlock(blockMap.blocks[index], in: text)
        }
        onBlocksChanged?()
    }

    // MARK: Styling

    private func style(blocksIntersecting range: NSRange) {
        guard let blockMap, let first = blockMap.blockIndex(at: range.location) else { return }
        let text: NSString = storage.mutableString
        var index = first
        while index < blockMap.blocks.count, blockMap.blocks[index].range.location <= NSMaxRange(range) {
            styleBlock(blockMap.blocks[index], in: text)
            index += 1
        }
    }

    private func scheduleBackgroundStyling() {
        guard !isStylingScheduled, backgroundOffset != nil else { return }
        isStylingScheduled = true
        // A timer in the default mode: no work while the user scrolls or drags (tracking mode),
        // and the run loop still goes to sleep between chunks, so every chunk ends with a frame.
        // (`RunLoop.perform` blocks keep the loop polling: no display until the whole pass ended.)
        let timer = Timer(timeInterval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isStylingScheduled = false
                self?.styleNextChunk()
            }
        }
        RunLoop.main.add(timer, forMode: .default)
    }

    /// Styles blocks for about 4 ms, then yields to the run loop.
    private func styleNextChunk() {
        guard let offset = backgroundOffset, let blockMap else { return }
        let chunkStart = ContinuousClock.now
        defer {
            let chunk = ContinuousClock.now - chunkStart
            backgroundStats.chunks += 1
            backgroundStats.longest = max(backgroundStats.longest, chunk)
            if backgroundOffset == nil {
                let total = (ContinuousClock.now - backgroundStats.started).milliseconds
                let longest = backgroundStats.longest.milliseconds
                Performance.logger.notice("""
                    Background highlight done: \(total, format: .fixed(precision: 0)) ms, \
                    \(self.backgroundStats.chunks) chunks, longest \(longest, format: .fixed(precision: 1)) ms
                    """)
            }
        }
        let deadline = chunkStart + .milliseconds(4)
        let text: NSString = storage.mutableString
        guard var index = blockMap.blockIndex(at: offset) else {
            backgroundOffset = nil
            return
        }
        if blockMap.blocks[index].range.location < offset { index += 1 }
        // After a theme change every character still has the old theme's attributes: reset from
        // where the last chunk stopped to the end of each block (blank lines between blocks too).
        var cursor = offset
        storage.beginEditing()
        while index < blockMap.blocks.count, ContinuousClock.now < deadline {
            let block = blockMap.blocks[index]
            if resetsInBackground { resetBase(from: cursor, to: NSMaxRange(block.range)) }
            styleBlock(block, in: text)
            cursor = NSMaxRange(block.range)
            index += 1
        }
        if index >= blockMap.blocks.count, resetsInBackground { resetBase(from: cursor, to: text.length) }
        storage.endEditing()
        if index < blockMap.blocks.count {
            backgroundOffset = resetsInBackground ? cursor : blockMap.blocks[index].range.location
            scheduleBackgroundStyling()
        } else {
            backgroundOffset = nil
            resetsInBackground = false
        }
    }

    /// Base attributes for `from..<to`, leaving front matter (styled as YAML) alone.
    private func resetBase(from start: Int, to end: Int) {
        let lower = max(start, frontMatterEnd)
        let upper = min(end, storage.length)
        guard lower < upper else { return }
        storage.setAttributes(theme.baseAttributes, range: NSRange(location: lower, length: upper - lower))
    }

    /// Colours one block, except inside front matter (styled as YAML instead).
    private func styleBlock(_ block: MarkdownBlock, in text: NSString) {
        guard block.range.location >= frontMatterEnd else { return }
        apply(Highlighter.spans(for: block, in: text))
        requestCodeHighlight(for: block, in: text)
    }

    private func apply(_ spans: [HighlightSpan]) {
        let length = storage.length
        // Spans that change the font, to combine traits of nested spans (bold inside a heading).
        var fontSpans: [(range: NSRange, attributes: EditorTheme.TokenAttributes)] = []
        for span in spans where NSMaxRange(span.range) <= length {
            let attributes = theme.attributes(for: span.token)
            if let foreground = attributes.foreground {
                storage.addAttribute(.foregroundColor, value: foreground, range: span.range)
            }
            if let background = attributes.background {
                storage.addAttribute(.backgroundColor, value: background, range: span.range)
            }
            if attributes.isStrikethrough {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.range)
            }
            if attributes.isBold || attributes.isItalic || attributes.fontSize != nil {
                let enclosing = fontSpans.filter {
                    NSLocationInRange(span.range.location, $0.range) && NSMaxRange(span.range) <= NSMaxRange($0.range)
                }
                storage.addAttribute(.font, value: font(for: attributes, inside: enclosing.map(\.attributes)),
                                     range: span.range)
                fontSpans.append((span.range, attributes))
            }
        }
    }

    /// Spans come outermost first, so a span's font combines the traits of every enclosing font span
    /// (bold inside a heading keeps the heading size). Reading the current font from the storage
    /// instead would force AppKit to fix attributes during processEditing (2–3 ms per keystroke in a
    /// heading, Time Profiler 2026-09-24).
    private func font(for attributes: EditorTheme.TokenAttributes,
                      inside enclosing: [EditorTheme.TokenAttributes]) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        var size = theme.baseFont.pointSize
        for layer in enclosing + [attributes] {
            if layer.isBold { traits.insert(.bold) }
            if layer.isItalic { traits.insert(.italic) }
            if let layerSize = layer.fontSize { size = layerSize }
        }
        return font(traits: traits, size: size)
    }

    private func font(traits: NSFontDescriptor.SymbolicTraits, size: CGFloat) -> NSFont {
        let key = FontKey(traits: traits.rawValue, size: size)
        if let cached = fontCache[key] { return cached }
        let descriptor = theme.baseFont.fontDescriptor.withSymbolicTraits(traits)
        let font = NSFont(descriptor: descriptor, size: size) ?? theme.baseFont
        fontCache[key] = font
        return font
    }
}

/// Hands a block map built off the main thread over to it. The map is created and last touched
/// inside the detached task, then used only on the main actor: ownership moves, nothing is shared.
private final class ParsedBlockMap: @unchecked Sendable {
    let map: BlockMap

    init(map: BlockMap) {
        self.map = map
    }
}
