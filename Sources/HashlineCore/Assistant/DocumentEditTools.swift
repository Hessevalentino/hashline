import Foundation

/// The assistant's tools for changing its document (ADR 0019): a replacement of an exact passage
/// and a rewrite of the whole text. They act on this one document and nothing else.
public enum DocumentEditTools {
    public static let editName = "edit_document"
    public static let rewriteName = "rewrite_document"

    public static let all: [AssistantTool] = [
        AssistantTool(
            name: editName,
            description: """
                Replace one passage of the document with new text. `original` must be copied exactly from \
                the current document (including Markdown syntax and line breaks) and must occur exactly once; \
                include enough surrounding words to make it unique. Keep passages short: several small edits \
                are better than one large one. The change is applied immediately and the user can undo it.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "original": ["type": "string", "description": "Exact text currently in the document."],
                    "replacement": ["type": "string", "description": "The new text (may be empty to delete)."],
                ],
                "required": ["original", "replacement"],
                "additionalProperties": false,
            ]),
        AssistantTool(
            name: rewriteName,
            description: """
                Replace the whole document with new Markdown text. Use it only when most of the document \
                changes (a full rewrite or translation); otherwise use edit_document.
                """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "The complete new document."],
                ],
                "required": ["text"],
                "additionalProperties": false,
            ]),
    ]

    public enum Failure: Error, Equatable {
        case invalidInput
        case notFound
        case ambiguous(count: Int)
        case unknownTool(String)

        /// Tells the model what to do instead (sent back as the tool result).
        public var message: String {
            switch self {
            case .invalidInput:
                "The tool input was incomplete or not valid JSON. Nothing was changed; try again."
            case .notFound:
                """
                `original` was not found in the current document. Nothing was changed. Copy the passage \
                exactly as it is now (earlier edits may have changed it).
                """
            case .ambiguous(let count):
                """
                `original` occurs \(count) times. Nothing was changed. Include more surrounding text so it \
                is unique.
                """
            case .unknownTool(let name):
                "There is no tool named \(name)."
            }
        }
    }

    /// The edit a tool call makes in `text`, trimmed to the characters that actually change.
    public static func edit(for name: String, input: JSONValue, in text: NSString) -> Result<TextEdit, Failure> {
        switch name {
        case editName:
            guard let original = input["original"]?.string, let replacement = input["replacement"]?.string,
                  !original.isEmpty else { return .failure(.invalidInput) }
            return locate(original, in: text).map { minimalEdit(in: text, range: $0, replacement: replacement) }
        case rewriteName:
            guard let replacement = input["text"]?.string else { return .failure(.invalidInput) }
            return .success(minimalEdit(in: text, range: NSRange(location: 0, length: text.length),
                                        replacement: replacement))
        default:
            return .failure(.unknownTool(name))
        }
    }

    /// The only occurrence of `original`.
    static func locate(_ original: String, in text: NSString) -> Result<NSRange, Failure> {
        let first = text.range(of: original, options: .literal)
        guard first.location != NSNotFound else { return .failure(.notFound) }
        var count = 1
        var searchStart = first.location + 1
        while searchStart < text.length {
            let next = text.range(of: original, options: .literal,
                                  range: NSRange(location: searchStart, length: text.length - searchStart))
            guard next.location != NSNotFound else { break }
            count += 1
            searchStart = next.location + 1
        }
        return count == 1 ? .success(first) : .failure(.ambiguous(count: count))
    }

    /// Replaces `range` with `replacement`, leaving out the prefix and suffix they share (whole
    /// composed characters), so the undo, the restyling and the highlight cover only real changes.
    /// The selection afterwards is the changed text.
    public static func minimalEdit(in text: NSString, range: NSRange, replacement: String) -> TextEdit {
        let old = text.substring(with: range) as NSString
        let new = replacement as NSString
        var prefix = 0
        let limit = min(old.length, new.length)
        while prefix < limit, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < limit - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        // Never split a surrogate pair or a composed character: move both cuts outwards to boundaries.
        while true {
            let start = min(boundary(in: old, before: prefix), boundary(in: new, before: prefix))
            if start == prefix { break }
            prefix = start
        }
        while true {
            let shift = max(boundary(in: old, after: old.length - suffix) - (old.length - suffix),
                            boundary(in: new, after: new.length - suffix) - (new.length - suffix))
            if shift == 0 { break }
            suffix -= shift
        }

        let changed = NSRange(location: range.location + prefix, length: old.length - prefix - suffix)
        let inserted = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
        return TextEdit(range: changed, replacement: inserted,
                        selection: NSRange(location: changed.location, length: (inserted as NSString).length))
    }

    /// The start of the composed character containing `offset` (or `offset` at a boundary).
    private static func boundary(in string: NSString, before offset: Int) -> Int {
        guard offset > 0, offset < string.length else { return offset }
        return string.rangeOfComposedCharacterSequence(at: offset).location
    }

    /// The end of the composed character that starts before `offset` and contains it.
    private static func boundary(in string: NSString, after offset: Int) -> Int {
        guard offset > 0, offset < string.length else { return offset }
        let range = string.rangeOfComposedCharacterSequence(at: offset)
        return range.location == offset ? offset : NSMaxRange(range)
    }
}
