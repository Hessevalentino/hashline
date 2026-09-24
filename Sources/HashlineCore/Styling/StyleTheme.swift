import Foundation

/// Editor theme in MacDown's `.style` format (from peg-markdown-highlight):
/// sections named by an element (`editor`, `H1`, `STRONG`, …) followed by `key: value` lines.
public struct StyleTheme: Sendable, Equatable {
    public struct Color: Sendable, Equatable {
        public let red, green, blue, alpha: Double

        /// `rrggbb` or `rrggbbaa`, with or without `#`.
        public init?(hex: String) {
            let digits = hex.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
            let hasAlpha = digits.count == 8
            let rgb = hasAlpha ? value >> 8 : value
            red = Double((rgb >> 16) & 0xFF) / 255
            green = Double((rgb >> 8) & 0xFF) / 255
            blue = Double(rgb & 0xFF) / 255
            alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1
        }

        var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
    }

    public struct Style: Sendable, Equatable {
        public var foreground: Color?
        public var background: Color?
        public var isBold = false
        public var isItalic = false
        public var fontSize: Double?
        public var caret: Color?
    }

    public let name: String
    public private(set) var styles: [String: Style] = [:]

    public init(name: String, source: String) {
        self.name = name
        var current: String?
        for rawLine in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let colon = line.firstIndex(of: ":") else {
                current = line
                if styles[line] == nil { styles[line] = Style() }
                continue
            }
            guard let section = current else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            Self.apply(key: key, value: value, to: &styles[section, default: Style()])
        }
    }

    /// A theme from already parsed sections (Hashline's `theme.json`).
    public init(name: String, styles: [String: Style]) {
        self.name = name
        self.styles = styles
    }

    public var editor: Style { styles["editor"] ?? Style() }
    public var selection: Style? { styles["editor-selection"] }

    public func style(for token: HighlightToken) -> Style? {
        styles[token.rawValue]
    }

    public var isDark: Bool { (editor.background?.luminance ?? 1) < 0.5 }

    private static func apply(key: String, value: String, to style: inout Style) {
        switch key {
        case "foreground", "color": style.foreground = Color(hex: value)
        case "background": style.background = Color(hex: value)
        case "caret": style.caret = Color(hex: value)
        case "font-size": style.fontSize = Double(value.lowercased().replacingOccurrences(of: "px", with: "")
                                                        .trimmingCharacters(in: .whitespaces))
        case "font-style":
            let parts = value.lowercased().split(whereSeparator: { $0 == "," || $0 == " " })
            style.isBold = parts.contains("bold")
            style.isItalic = parts.contains("italic")
        default: break
        }
    }
}
