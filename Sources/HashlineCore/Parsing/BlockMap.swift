import Foundation
import Markdown

/// One parse of a slice of the document. Node locations inside it are relative to the slice.
final class ParsedFragment {
    let document: Document
    let lineIndex: LineIndex
    /// Unique per BlockMap; identifies blocks that were not reparsed (see `MarkdownBlock.id`).
    let serial: Int

    init(text: String, serial: Int) {
        // No smart punctuation: the preview must show the quotes and dashes the user typed.
        // Hostile nesting is neutralised first (same positions); see NestingGuard.
        document = Document(parsing: NestingGuard.defused(text), options: [.disableSmartOpts])
        lineIndex = LineIndex(text)
        self.serial = serial
    }
}

/// The code of a fenced block: range between the fences, text and language.
public struct FencedCode: Sendable {
    public let range: NSRange
    public let code: String
    public let language: String
}

/// A top-level block of the document.
public struct MarkdownBlock {
    /// UTF-16 range in the document.
    public private(set) var range: NSRange
    public let markup: Markup
    let fragment: ParsedFragment
    /// Document offset of the fragment's first character.
    private(set) var base: Int
    /// cmark-gfm reports inline positions of a paragraph that starts with link reference
    /// definitions as if the definitions were not there: this many lines too early.
    private let inlineLineShift: Int

    /// Stable while the block is not reparsed; changes whenever its content may have changed.
    public let id: String

    init?(markup: Markup, fragment: ParsedFragment, base: Int) {
        self.markup = markup
        self.fragment = fragment
        self.base = base
        id = "b\(fragment.serial)-\(markup.indexInParent)"
        guard let sourceRange = markup.range else { return nil }
        let index = fragment.lineIndex
        let start = index.utf16Offset(line: sourceRange.lowerBound.line, column: sourceRange.lowerBound.column)
        let end = index.utf16Offset(line: sourceRange.upperBound.line, column: sourceRange.upperBound.column)
        range = NSRange(location: base + start, length: max(end - start, 0))
        inlineLineShift = markup is Paragraph
            ? Self.leadingDefinitionLines(from: sourceRange.lowerBound.line, to: sourceRange.upperBound.line,
                                          in: fragment.lineIndex)
            : 0
    }

    private static func leadingDefinitionLines(from first: Int, to last: Int, in index: LineIndex) -> Int {
        var count = 0
        while first + count < last, BlockMap.isDefinitionLine(index.text(ofLine: first + count)) { count += 1 }
        return count
    }

    /// Document range of any node inside this block.
    public func range(of node: Markup) -> NSRange? {
        guard let sourceRange = node.range else { return nil }
        let index = fragment.lineIndex
        let shift = inlineLineShift > 0 && node.parent != nil && !(node is Paragraph) ? inlineLineShift : 0
        let start = index.utf16Offset(line: sourceRange.lowerBound.line + shift, column: sourceRange.lowerBound.column)
        let end = index.utf16Offset(line: sourceRange.upperBound.line + shift, column: sourceRange.upperBound.column)
        return NSRange(location: base + start, length: max(end - start, 0))
    }

    /// Source text of a node (as written, with markers).
    public func source(of node: Markup) -> String? {
        guard let sourceRange = node.range else { return nil }
        let shift = inlineLineShift > 0 && node.parent != nil && !(node is Paragraph) ? inlineLineShift : 0
        let start = sourceRange.lowerBound
        let end = sourceRange.upperBound
        return fragment.lineIndex.text(fromLine: start.line + shift, column: start.column,
                                       toLine: end.line + shift, column: end.column)
    }

    /// 1-based line of a node within the block's fragment, used to detect blank lines between siblings.
    func fragmentLines(of node: Markup) -> ClosedRange<Int>? {
        guard let sourceRange = node.range else { return nil }
        return sourceRange.lowerBound.line...max(sourceRange.lowerBound.line, sourceRange.upperBound.line)
    }

    /// For a top-level fenced code block with a language: the range of its code (between the
    /// fences) and the language. Indented fences are skipped: their code has indentation removed.
    public func fencedCode(in text: NSString) -> FencedCode? {
        guard let code = markup as? CodeBlock,
              let language = code.language?.split(separator: " ").first.map(String.init), !language.isEmpty,
              range.location < text.length else { return nil }
        let fence = text.character(at: range.location)
        guard fence == 0x60 || fence == 0x7E else { return nil }  // ` or ~
        let firstLine = text.lineRange(for: NSRange(location: range.location, length: 0))
        let start = NSMaxRange(firstLine)
        let length = min((code.code as NSString).length, max(NSMaxRange(range) - start, 0))
        guard length > 0 else { return nil }
        return FencedCode(range: NSRange(location: start, length: length), code: code.code, language: language)
    }

    mutating func shift(by delta: Int) {
        base += delta
        range.location += delta
    }

    mutating func clamp(toEnd end: Int) {
        if NSMaxRange(range) > end { range.length = max(end - range.location, 0) }
    }
}

/// Top-level blocks of a document, kept up to date by reparsing only the edited area.
public final class BlockMap {
    public private(set) var blocks: [MarkdownBlock] = []
    /// Link reference definitions apply document-wide but are not part of the AST,
    /// so they are appended to every partially parsed slice.
    private(set) var definitions: [String] = []
    /// Incremented when definitions change; rendered output that resolves links must be invalidated.
    public private(set) var definitionsVersion = 0
    /// After `applyEdit`: indices of replaced blocks whose content may differ. Neighbours that were
    /// reparsed only for context (same type, same length, untouched by the edit) are left out,
    /// so the editor does not restyle and relayout them.
    public private(set) var lastChangedBlocks: [Int] = []
    /// Whether the text may contain a definition (`]:`). Lets the full check skip documents
    /// that have none, which is most of them.
    private var mayHaveDefinitions = false
    private var nextSerial = 0

    public init(text: String) {
        reparseAll(text as NSString)
    }

    /// Updates the map after an edit.
    /// - Parameters:
    ///   - editedRange: range of the new text, in post-edit coordinates
    ///   - delta: change in length (new length − old length)
    ///   - replacedText: the text that was replaced (before the edit)
    ///   - text: the whole document after the edit
    /// - Returns: the index range of blocks that were replaced; everything else only shifted.
    @discardableResult
    public func applyEdit(editedRange: NSRange, delta: Int, replacedText: String, in text: NSString) -> Range<Int> {
        let editStart = editedRange.location
        let oldEditEnd = NSMaxRange(editedRange) - delta
        let newLength = text.length

        guard !blocks.isEmpty else {
            reparseAll(text)
            lastChangedBlocks = Array(0..<blocks.count)
            return 0..<blocks.count
        }

        // Include one block on each side: setext underlines, lazy continuation and
        // list continuation can change the neighbouring block.
        let touching = blocks.firstIndex { NSMaxRange($0.range) >= editStart } ?? blocks.count - 1
        let first = max(touching - 1, 0)
        let lastTouched = blocks.lastIndex { $0.range.location <= oldEditEnd } ?? 0
        var last = min(max(lastTouched, first) + 1, blocks.count - 1)

        // Start at a line start: blocks may begin after indentation (indented code, list markers).
        let regionStart = text.lineRange(for: NSRange(location: min(blocks[first].range.location, editStart),
                                                      length: 0)).location
        let definitionsMayChange = replacedText.contains("]:")

        while true {
            let regionEndOld = last + 1 < blocks.count ? blocks[last + 1].range.location : newLength - delta
            let regionEnd = min(max(regionEndOld + delta, NSMaxRange(editedRange)), newLength)
            let region = NSRange(location: regionStart, length: regionEnd - regionStart)

            let regionHasColon = text.substring(with: region).contains("]:")
            if regionHasColon { mayHaveDefinitions = true }
            if definitionsMayChange || regionHasColon {
                let before = definitions
                reparseAll(text)
                if definitions != before { definitionsVersion += 1 }
                lastChangedBlocks = Array(0..<blocks.count)
                return 0..<blocks.count
            }

            let parsed = parse(text, range: region)
            let reachedEnd = regionEnd >= newLength
            let stable = reachedEnd || last == blocks.count - 1
                || (parsed.last.map { NSEqualRanges($0.range, NSRange(location: blocks[last].range.location + delta,
                                                                       length: blocks[last].range.length)) } ?? false)
            if stable {
                let old = blocks[first...last].map { (type: type(of: $0.markup), range: $0.range) }
                blocks.replaceSubrange(first...last, with: parsed)
                let replaced = first..<(first + parsed.count)
                lastChangedBlocks = replaced.filter { !isUnchangedNeighbour(blocks[$0], old: old, edit: editedRange,
                                                                            delta: delta) }
                for index in replaced.upperBound..<blocks.count {
                    blocks[index].shift(by: delta)
                }
                return replaced
            }
            // The edit changed how following blocks parse (e.g. an unclosed code fence): widen.
            last = min(last + max(last - first, 1), blocks.count - 1)
        }
    }

    /// A block reparsed only for context: untouched by the edit and, before it, of the same type
    /// with the same text span.
    private func isUnchangedNeighbour(_ block: MarkdownBlock, old: [(type: Markup.Type, range: NSRange)],
                                      edit: NSRange, delta: Int) -> Bool {
        let touched = NSMaxRange(block.range) >= edit.location && block.range.location <= NSMaxRange(edit)
        guard !touched else { return false }
        let oldLocation = block.range.location < edit.location ? block.range.location : block.range.location - delta
        return old.contains {
            $0.type == type(of: block.markup) && $0.range.location == oldLocation
                && $0.range.length == block.range.length
        }
    }

    /// Full check of link reference definitions, too slow for every keystroke but cheap enough
    /// for the debounced preview update. `applyEdit` catches common cases immediately; edits that
    /// create or break a definition indirectly are caught here.
    /// - Returns: true when definitions changed and the whole document was reparsed.
    @discardableResult
    public func validateDefinitions(in text: NSString) -> Bool {
        guard mayHaveDefinitions || !definitions.isEmpty else { return false }
        let current = Self.scanDefinitions(in: text, outside: blocks)
        guard current != definitions else { return false }
        reparseAll(text)
        definitionsVersion += 1
        return true
    }

    /// Index of the block containing or following the UTF-16 offset.
    public func blockIndex(at offset: Int) -> Int? {
        guard !blocks.isEmpty else { return nil }
        var low = 0
        var high = blocks.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if blocks[mid].range.location <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Full parse: cmark resolves definitions itself; they are then collected for partial parses.
    private func reparseAll(_ text: NSString) {
        blocks = parse(text, range: NSRange(location: 0, length: text.length), appendingDefinitions: false)
        mayHaveDefinitions = text.range(of: "]:").location != NSNotFound
        definitions = Self.scanDefinitions(in: text, outside: blocks)
    }

    /// Parses a slice. Definitions go in front, separated by a blank line: behind the slice an
    /// unclosed code fence would swallow them into its content.
    private func parse(_ text: NSString, range: NSRange, appendingDefinitions: Bool = true) -> [MarkdownBlock] {
        // One paragraph per definition: a line that only looks like one must not swallow the next.
        let prefix = appendingDefinitions && !definitions.isEmpty ? definitions.joined(separator: "\n\n") + "\n\n" : ""
        let prefixLength = (prefix as NSString).length
        nextSerial += 1
        let fragment = ParsedFragment(text: prefix + text.substring(with: range), serial: nextSerial)
        let regionEnd = NSMaxRange(range)
        var result: [MarkdownBlock] = []
        for child in fragment.document.children {
            guard var block = MarkdownBlock(markup: child, fragment: fragment, base: range.location - prefixLength),
                  block.range.location >= range.location, block.range.location < regionEnd else { continue }
            block.clamp(toEnd: regionEnd)
            result.append(block)
        }
        return result
    }

    private static let definitionStart = try? NSRegularExpression(pattern: #"^ {0,3}\["#)

    static func isDefinitionLine(_ line: String) -> Bool {
        let length = (line as NSString).length
        return line.contains("]:")
            && definitionStart?.firstMatch(in: line, range: NSRange(location: 0, length: length)) != nil
    }

    /// Link reference definitions are exactly the text cmark consumed without producing a block:
    /// the gaps between blocks and the start of a paragraph before its first inline content.
    /// Reading them from block positions is exact, unlike matching definition syntax.
    static func scanDefinitions(in text: NSString, outside blocks: [MarkdownBlock]) -> [String] {
        guard text.range(of: "]:").location != NSNotFound else { return [] }
        var chunks: [NSRange] = []
        var cursor = 0
        for block in blocks {
            if block.range.location > cursor {
                chunks.append(NSRange(location: cursor, length: block.range.location - cursor))
            }
            if block.markup is Paragraph, let first = block.markup.child(at: 0),
               let contentStart = block.range(of: first)?.location, contentStart > block.range.location {
                chunks.append(NSRange(location: block.range.location, length: contentStart - block.range.location))
            }
            cursor = max(cursor, NSMaxRange(block.range))
        }
        if text.length > cursor { chunks.append(NSRange(location: cursor, length: text.length - cursor)) }
        return chunks.compactMap { range in
            let chunk = text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            // Only definitions: never re-inject anything else (e.g. an unclosed fence) into partial parses.
            return isDefinitionLine(chunk) ? chunk : nil
        }
    }
}
