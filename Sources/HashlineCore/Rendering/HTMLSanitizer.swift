import Foundation

/// Allow-list sanitizer for raw HTML in Markdown. Allowed tags keep only safe attributes; any
/// other tag is shown as text (escaped); comments are dropped. Defence in depth: the preview also
/// runs without page JavaScript and with a strict Content Security Policy.
public enum HTMLSanitizer {
    /// Tag → allowed attributes.
    static let allowed: [String: Set<String>] = [
        "img": ["src", "alt", "title", "width", "height", "style"],
        "br": [], "kbd": [], "sub": [], "sup": [], "mark": [], "u": [], "ins": [], "del": [], "s": [],
        "b": [], "i": [], "em": [], "strong": [], "code": [], "small": [],
        "details": ["open"], "summary": [],
        "a": ["href", "title"],
    ]

    /// A comment, or a tag: name (group 1) and its attributes (group 2).
    private static let tagPattern = try? NSRegularExpression(
        pattern: #"<!--[\s\S]*?-->|</?([A-Za-z][A-Za-z0-9-]*)"#
            + #"((?:\s+[^\s"'>/=]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'>]+))?)*)\s*/?>"#
    )
    private static let attributePattern = try? NSRegularExpression(
        pattern: #"([^\s"'>/=]+)(?:\s*=\s*("[^"]*"|'[^']*'|[^\s"'>]+))?"#
    )

    /// - Parameter imageSource: rewrites `<img src>` after it passed the URL check (preview paths).
    public static func sanitize(_ html: String, imageSource: ((String) -> String)? = nil) -> String {
        guard let tagPattern else { return escape(html) }
        let source = html as NSString
        var output = ""
        var cursor = 0
        for match in tagPattern.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let between = NSRange(location: cursor, length: match.range.location - cursor)
            output += escapeText(source.substring(with: between))
            cursor = NSMaxRange(match.range)
            let tag = source.substring(with: match.range)
            if tag.hasPrefix("<!--") { continue }
            let name = source.substring(with: match.range(at: 1)).lowercased()
            guard let attributes = allowed[name] else {
                output += escape(tag)
                continue
            }
            if tag.hasPrefix("</") {
                output += "</\(name)>"
                continue
            }
            let attributeRange = match.range(at: 2)
            let attributeText = attributeRange.location == NSNotFound ? "" : source.substring(with: attributeRange)
            let close = tag.hasSuffix("/>") ? " />" : ">"
            output += "<\(name)" + safeAttributes(attributeText, allowed: attributes,
                                                   imageSource: name == "img" ? imageSource : nil) + close
        }
        output += escapeText(source.substring(from: cursor))
        return output
    }

    private static func safeAttributes(_ text: String, allowed: Set<String>,
                                       imageSource: ((String) -> String)?) -> String {
        guard let attributePattern, !text.isEmpty else { return "" }
        let source = text as NSString
        var result = ""
        for match in attributePattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let name = source.substring(with: match.range(at: 1)).lowercased()
            guard allowed.contains(name) else { continue }
            var value = match.range(at: 2).location == NSNotFound ? "" : source.substring(with: match.range(at: 2))
            if value.hasPrefix("\"") || value.hasPrefix("'") { value = String(value.dropFirst().dropLast()) }
            value = decodeBasicEntities(value)
            switch name {
            case "src", "href":
                guard isSafeURL(value, allowImageData: name == "src") else { continue }
                if name == "src", let imageSource { value = imageSource(value) }
            case "style":
                value = safeStyle(value)
                guard !value.isEmpty else { continue }
            default:
                break
            }
            result += " \(name)=\"\(escape(value))\""
        }
        return result
    }

    static func isSafeURL(_ value: String, allowImageData: Bool) -> Bool {
        let compact = value.lowercased().filter { !$0.isWhitespace && !$0.isNewline && $0 != "\u{0}" }
        if compact.hasPrefix("data:") {
            return allowImageData && compact.hasPrefix("data:image/") && !compact.hasPrefix("data:image/svg")
        }
        // A scheme is the text before a ":" that precedes any "/", "?" or "#"; otherwise it is relative.
        guard let colon = compact.firstIndex(of: ":") else { return true }
        if let separator = compact.firstIndex(where: { "/?#".contains($0) }), separator < colon { return true }
        return ["http", "https", "mailto", "file"].contains(String(compact[..<colon]))
    }

    /// Only size declarations (`zoom`, `width`, `height`, `max-width`) survive.
    private static func safeStyle(_ style: String) -> String {
        style.split(separator: ";").compactMap { declaration -> String? in
            let parts = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let isSize = parts.count == 2
                && parts[1].range(of: #"^[0-9.]+(%|px|em|rem)?$"#, options: .regularExpression) != nil
            guard isSize, ["zoom", "width", "height", "max-width"].contains(parts[0].lowercased()) else { return nil }
            return "\(parts[0].lowercased()): \(parts[1])"
        }.joined(separator: "; ")
    }

    private static func decodeBasicEntities(_ value: String) -> String {
        value.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Text between tags is already HTML text; only stray `<` and `>` are escaped.
    private static func escapeText(_ text: String) -> String {
        text.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
