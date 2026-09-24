import Foundation

/// Extensions found inside plain text runs: footnote references, GFM autolinks, emoji shortcodes
/// and the optional `==mark==` and `^sup^`.
public enum InlineExtension: Equatable, Sendable {
    case footnote(label: String)
    case autolink(url: String)
    case emoji(String)
    case mark(String)
    case superscript(String)
    case math(String)
}

public struct InlineExtensionMatch: Equatable, Sendable {
    /// UTF-16 range in the text run.
    public let range: NSRange
    public let kind: InlineExtension
}

public struct InlineExtensionSettings: Sendable, Equatable {
    public var highlight = false
    public var superscript = false
    public var subscriptText = false
    /// `$…$` inline math (on in the preview).
    public var math = false

    public init(highlight: Bool = false, superscript: Bool = false, subscriptText: Bool = false,
                math: Bool = false) {
        self.highlight = highlight
        self.superscript = superscript
        self.subscriptText = subscriptText
        self.math = math
    }
}

public enum InlineExtensions {
    private static let footnotePattern = try? NSRegularExpression(pattern: #"\[\^([^\]\s]+)\]"#)
    private static let emojiPattern = try? NSRegularExpression(pattern: #":([a-z0-9_+-]+):"#)
    private static let markPattern = try? NSRegularExpression(pattern: #"==(?=\S)(.+?)(?<=\S)=="#)
    private static let superscriptPattern = try? NSRegularExpression(pattern: #"\^([^\s^]+)\^"#)
    /// A footnote definition at the start of a paragraph: `[^label]: `.
    private static let definitionPattern = try? NSRegularExpression(pattern: #"^\[\^([^\]\s]+)\]:[ \t]*"#)

    /// Non-overlapping matches in document order; earlier kinds win on overlap.
    public static func matches(in text: String, settings: InlineExtensionSettings,
                               autolinks: Bool = true) -> [InlineExtensionMatch] {
        let string = text as NSString
        let whole = NSRange(location: 0, length: string.length)
        var found: [InlineExtensionMatch] = []
        func add(_ pattern: NSRegularExpression?, _ make: (NSTextCheckingResult) -> InlineExtension?) {
            for result in pattern?.matches(in: text, range: whole) ?? [] {
                let overlaps = found.contains { NSIntersectionRange($0.range, result.range).length > 0 }
                guard let kind = make(result), !overlaps else { continue }
                found.append(InlineExtensionMatch(range: result.range, kind: kind))
            }
        }
        if settings.math, text.contains("$") {
            add(MathSyntax.inlinePattern) { .math(string.substring(with: $0.range(at: 1))) }
        }
        if text.contains("[^") { add(footnotePattern) { .footnote(label: string.substring(with: $0.range(at: 1))) } }
        if autolinks {
            for link in Autolinker.matches(in: text)
            where !found.contains(where: { NSIntersectionRange($0.range, link.range).length > 0 }) {
                found.append(InlineExtensionMatch(range: link.range, kind: .autolink(url: link.url)))
            }
        }
        if text.contains(":") {
            add(emojiPattern) { Emoji.emoji(for: string.substring(with: $0.range(at: 1))).map(InlineExtension.emoji) }
        }
        if settings.highlight, text.contains("==") {
            add(markPattern) { .mark(string.substring(with: $0.range(at: 1))) }
        }
        if settings.superscript, text.contains("^") {
            add(superscriptPattern) { .superscript(string.substring(with: $0.range(at: 1))) }
        }
        return found.sorted { $0.range.location < $1.range.location }
    }

    /// Label and prefix length of a footnote definition at the start of `text`.
    public static func footnoteDefinition(in text: String) -> (label: String, prefixLength: Int)? {
        let string = text as NSString
        guard let match = definitionPattern?.firstMatch(in: text, range: NSRange(location: 0, length: string.length))
        else { return nil }
        return (string.substring(with: match.range(at: 1)), match.range.length)
    }
}

/// Heading anchors and the generated table of contents.
public enum TableOfContents {
    public struct Entry: Equatable, Sendable {
        public let level: Int
        public let title: String
        public let slug: String
    }

    /// GitHub-style anchor: lowercase, spaces to `-`, punctuation dropped, letters of any script kept.
    public static func slug(_ title: String) -> String {
        let lowered = title.lowercased()
        var result = ""
        for character in lowered {
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                result.append(character)
            } else if character == " " {
                result.append("-")
            }
        }
        return result
    }

    /// `[toc]` alone in a paragraph (case-insensitive).
    public static func isPlaceholder(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "[toc]"
    }

    public static func html(for entries: [Entry]) -> String {
        guard !entries.isEmpty else { return "<nav class=\"toc\"></nav>\n" }
        let base = entries.map(\.level).min() ?? 1
        var html = "<nav class=\"toc\">\n<ul>\n"
        var depth = 0
        for (index, entry) in entries.enumerated() {
            let level = entry.level - base
            if index > 0 {
                if level > depth {
                    for _ in depth..<level { html += "\n<ul>\n" }
                } else {
                    html += "</li>\n"
                    for _ in level..<depth { html += "</ul>\n</li>\n" }
                }
            }
            depth = level
            html += "<li><a href=\"#\(HTMLSanitizer.escape(entry.slug))\">\(HTMLSanitizer.escape(entry.title))</a>"
        }
        html += "</li>\n"
        for _ in 0..<depth { html += "</ul>\n</li>\n" }
        return html + "</ul>\n</nav>\n"
    }
}
