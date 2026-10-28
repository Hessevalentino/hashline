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

    /// Static SVG (diagrams pasted as code): shapes, text, gradients, markers and filters. No
    /// `script`, `foreignObject`, `image`, animation (`set`/`animate` rewrite attributes) or `<style>`
    /// (its CSS would apply to the whole page). Names are lowercase; the HTML parser restores the case.
    static let svgElements: Set<String> = [
        "svg", "g", "defs", "symbol", "use", "title", "desc", "switch",
        "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "text", "tspan", "textpath",
        "lineargradient", "radialgradient", "stop", "pattern", "clippath", "mask", "marker",
        "filter", "fegaussianblur", "feoffset", "feblend", "fecolormatrix", "feflood", "fecomposite",
        "femerge", "femergenode", "fedropshadow",
    ]
    static let svgAttributes: Set<String> = [
        "id", "width", "height", "x", "y", "x1", "y1", "x2", "y2", "cx", "cy", "r", "rx", "ry", "fx", "fy",
        "d", "points", "viewbox", "preserveaspectratio", "transform", "href", "xlink:href",
        "fill", "fill-opacity", "fill-rule", "stroke", "stroke-width", "stroke-opacity", "stroke-linecap",
        "stroke-linejoin", "stroke-dasharray", "stroke-dashoffset", "stroke-miterlimit", "opacity",
        "color", "display", "visibility", "clip-path", "clip-rule", "mask", "filter", "paint-order",
        "vector-effect", "shape-rendering", "text-rendering",
        "marker-start", "marker-mid", "marker-end", "markerwidth", "markerheight", "markerunits", "refx", "refy",
        "orient", "font-family", "font-size", "font-weight", "font-style", "text-anchor", "dominant-baseline",
        "alignment-baseline", "baseline-shift", "letter-spacing", "word-spacing", "text-decoration",
        "dx", "dy", "rotate", "textlength", "lengthadjust", "startoffset",
        "offset", "stop-color", "stop-opacity", "gradientunits", "gradienttransform", "spreadmethod",
        "patternunits", "patterncontentunits", "patterntransform", "clippathunits", "maskunits",
        "maskcontentunits", "filterunits", "primitiveunits", "in", "in2", "result", "stddeviation", "mode",
        "type", "values", "operator", "k1", "k2", "k3", "k4", "flood-color", "flood-opacity", "style",
    ]

    /// A comment, `<?xml …?>` or `<!DOCTYPE …>` (all dropped), or a tag: name (group 1) and its
    /// attributes (group 2).
    private static let tagPattern = try? NSRegularExpression(
        pattern: #"<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<![A-Za-z][^>]*>|</?([A-Za-z][A-Za-z0-9-]*)"#
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
            if tag.hasPrefix("<!") || tag.hasPrefix("<?") { continue }
            let name = source.substring(with: match.range(at: 1)).lowercased()
            let isSVG = allowed[name] == nil && svgElements.contains(name)
            guard let attributes = allowed[name] ?? (isSVG ? svgAttributes : nil) else {
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
            output += "<\(name)" + safeAttributes(attributeText, allowed: attributes, svg: isSVG,
                                                   imageSource: name == "img" ? imageSource : nil) + close
        }
        output += escapeText(source.substring(from: cursor))
        return output
    }

    private static func safeAttributes(_ text: String, allowed: Set<String>, svg: Bool,
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
            let safe = svg ? safeSVGAttribute(name, value) : safeHTMLAttribute(name, value, imageSource: imageSource)
            if let safe { result += " \(name)=\"\(escape(safe))\"" }
        }
        return result
    }

    private static func safeHTMLAttribute(_ name: String, _ value: String,
                                          imageSource: ((String) -> String)?) -> String? {
        switch name {
        case "src", "href":
            guard isSafeURL(value, allowImageData: name == "src") else { return nil }
            if name == "src", let imageSource { return imageSource(value) }
            return value
        case "style":
            let style = safeStyle(value)
            return style.isEmpty ? nil : style
        default:
            return value
        }
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

    /// References stay inside the document (`#gradient`); no URLs, no scripts in values.
    private static func safeSVGAttribute(_ name: String, _ value: String) -> String? {
        if name == "href" || name == "xlink:href", !value.hasPrefix("#") { return nil }
        let value = name == "style" ? safeSVGStyle(value) : value
        guard !(name == "style" && value.isEmpty), isSafeSVGValue(value) else { return nil }
        return value
    }

    /// SVG presentation in `style` (`fill: #fff; stroke-width: 2`); the value check is `isSafeSVGValue`.
    private static func safeSVGStyle(_ style: String) -> String {
        style.split(separator: ";").compactMap { declaration -> String? in
            let parts = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, svgAttributes.contains(parts[0].lowercased()), parts[0].lowercased() != "style",
                  isSafeSVGValue(parts[1]) else { return nil }
            return "\(parts[0].lowercased()): \(parts[1])"
        }.joined(separator: "; ")
    }

    /// `url(…)` only to a fragment in the document (`url(#g)`); no escapes, `expression()` or schemes.
    static func isSafeSVGValue(_ value: String) -> Bool {
        let compact = value.lowercased().filter { !$0.isWhitespace && $0 != "\u{0}" }
        if compact.contains("\\") || compact.contains("expression(") || compact.contains("javascript:") {
            return false
        }
        let fragments = compact.replacingOccurrences(of: "url(#", with: "")
            .replacingOccurrences(of: "url(\"#", with: "").replacingOccurrences(of: "url('#", with: "")
        return !fragments.contains("url(")
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
