import Foundation

/// A Hashline theme: `theme.json` in a `<Name>.hashlinetheme` folder next to `theme.css` (preview
/// and export). Colours are `#rrggbb` or `#rrggbbaa`; token names are the highlighter's (`H1`,
/// `STRONG`, `CODE`, `LINK`, …); code scopes are highlight.js classes (`keyword`, `string`, …).
public struct ThemeDefinition: Codable, Sendable, Equatable {
    public enum Appearance: String, Codable, Sendable {
        case light, dark
    }

    public struct TokenStyle: Codable, Sendable, Equatable {
        public var color: String?
        public var background: String?
        public var bold: Bool?
        public var italic: Bool?
        /// Size in points for the default 14 pt editor font; scaled with the user's font size.
        public var size: Double?
    }

    public struct Editor: Codable, Sendable, Equatable {
        public var background: String
        public var foreground: String
        public var caret: String?
        public var selection: String?
        public var selectionText: String?
        public var tokens: [String: TokenStyle]

        public init(background: String, foreground: String, caret: String? = nil, selection: String? = nil,
                    selectionText: String? = nil, tokens: [String: TokenStyle]) {
            self.background = background
            self.foreground = foreground
            self.caret = caret
            self.selection = selection
            self.selectionText = selectionText
            self.tokens = tokens
        }
    }

    public var name: String
    public var appearance: Appearance
    public var editor: Editor
    /// highlight.js scope → colour for fenced code in the editor.
    public var code: [String: String]

    public init(name: String, appearance: Appearance, editor: Editor, code: [String: String]) {
        self.name = name
        self.appearance = appearance
        self.editor = editor
        self.code = code
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case invalidJSON(String)
        case invalidColor(String)
        case unknownToken(String)

        public var description: String {
            switch self {
            case .invalidJSON(let detail): "theme.json is not valid: \(detail)"
            case .invalidColor(let value): "“\(value)” is not a colour (use #rrggbb)"
            case .unknownToken(let name): "Unknown token “\(name)”"
            }
        }
    }

    /// Parses and validates `theme.json`, so a typo is reported instead of silently ignored.
    public static func decode(_ data: Data) throws -> ThemeDefinition {
        let definition: ThemeDefinition
        do {
            definition = try JSONDecoder().decode(ThemeDefinition.self, from: data)
        } catch {
            throw Failure.invalidJSON(String(describing: error))
        }
        let known = Set(HighlightToken.allCases.map(\.rawValue))
        for name in definition.editor.tokens.keys where !known.contains(name) { throw Failure.unknownToken(name) }
        let colors = [definition.editor.background, definition.editor.foreground]
            + [definition.editor.caret, definition.editor.selection, definition.editor.selectionText].compactMap { $0 }
            + definition.editor.tokens.values.flatMap { [$0.color, $0.background].compactMap { $0 } }
            + Array(definition.code.values)
        for color in colors where StyleTheme.Color(hex: color) == nil { throw Failure.invalidColor(color) }
        return definition
    }

    /// The editor part as a `StyleTheme`, which the highlighter already understands.
    public var styleTheme: StyleTheme {
        var styles: [String: StyleTheme.Style] = [:]
        var editorStyle = StyleTheme.Style()
        editorStyle.background = StyleTheme.Color(hex: editor.background)
        editorStyle.foreground = StyleTheme.Color(hex: editor.foreground)
        editorStyle.caret = editor.caret.flatMap(StyleTheme.Color.init(hex:))
        styles["editor"] = editorStyle
        if editor.selection != nil || editor.selectionText != nil {
            var selection = StyleTheme.Style()
            selection.background = editor.selection.flatMap(StyleTheme.Color.init(hex:))
            selection.foreground = editor.selectionText.flatMap(StyleTheme.Color.init(hex:))
            styles["editor-selection"] = selection
        }
        for (name, token) in editor.tokens {
            var style = StyleTheme.Style()
            style.foreground = token.color.flatMap(StyleTheme.Color.init(hex:))
            style.background = token.background.flatMap(StyleTheme.Color.init(hex:))
            style.isBold = token.bold ?? false
            style.isItalic = token.italic ?? false
            style.fontSize = token.size
            styles[name] = style
        }
        return StyleTheme(name: name, styles: styles)
    }
}
