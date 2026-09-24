import Foundation

/// GFM extended autolinks (`www.`, `http(s)://`, e-mail) in plain text, which swift-markdown's
/// cmark-gfm build does not enable. Follows the GFM rules for trailing punctuation and parentheses.
public enum Autolinker {
    public struct Match: Equatable, Sendable {
        /// UTF-16 range in the searched text.
        public let range: NSRange
        public let url: String
    }

    // A URL may start only at the beginning or after whitespace or `*`, `_`, `~`, `(`.
    private static let urlPattern = try? NSRegularExpression(
        pattern: #"(?<=^|[\s*_~(])(?:https?://|www\.)[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*[^\s<]*"#
    )
    private static let emailPattern = try? NSRegularExpression(
        pattern: #"(?<=^|[\s*_~(])[A-Za-z0-9.+_-]+@[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+"#
    )

    public static func matches(in text: String) -> [Match] {
        guard text.contains(".") else { return [] }
        let string = text as NSString
        let whole = NSRange(location: 0, length: string.length)
        var matches: [Match] = []
        for result in urlPattern?.matches(in: text, range: whole) ?? [] {
            let trimmed = trimTrailing(result.range, in: string)
            guard trimmed.length > 0 else { continue }
            let link = string.substring(with: trimmed)
            // The domain needs a dot after `www.`/scheme and no underscore in its last two segments.
            let domain = link.replacingOccurrences(of: #"^(https?://)"#, with: "", options: .regularExpression)
                .split(separator: "/").first ?? ""
            let segments = domain.split(separator: ".")
            guard segments.count >= 2, !segments.suffix(2).contains(where: { $0.contains("_") }) else { continue }
            matches.append(Match(range: trimmed, url: link.hasPrefix("www.") ? "http://" + link : link))
        }
        for result in emailPattern?.matches(in: text, range: whole) ?? [] {
            var range = result.range
            let email = string.substring(with: range)
            guard let last = email.last, last != "-", last != "_" else { continue }
            if email.hasSuffix(".") { range.length -= 1 }
            guard !matches.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) else { continue }
            matches.append(Match(range: range, url: "mailto:" + string.substring(with: range)))
        }
        return matches.sorted { $0.range.location < $1.range.location }
    }

    /// Drops trailing `?!.,:*_~`, unbalanced `)` and a trailing entity reference like `&amp;`.
    private static func trimTrailing(_ range: NSRange, in text: NSString) -> NSRange {
        var end = NSMaxRange(range)
        while end > range.location {
            let link = text.substring(with: NSRange(location: range.location, length: end - range.location))
            guard let last = link.last else { break }
            if "?!.,:*_~\"'".contains(last) {
                end -= 1
            } else if last == ")" {
                let open = link.filter { $0 == "(" }.count
                let close = link.filter { $0 == ")" }.count
                if close > open { end -= 1 } else { break }
            } else if last == ";", let amp = link.range(of: #"&[A-Za-z0-9]+;$"#, options: .regularExpression) {
                end -= (String(link[amp]) as NSString).length
            } else {
                break
            }
        }
        return NSRange(location: range.location, length: end - range.location)
    }
}
