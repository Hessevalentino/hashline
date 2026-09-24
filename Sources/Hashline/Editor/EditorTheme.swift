import AppKit
import HashlineCore

/// A theme (`theme.json`) resolved to AppKit attributes for the editor font the user chose.
/// Attributes are display-only and never reach the file.
@MainActor
final class EditorTheme {
    let style: StyleTheme
    let isDark: Bool
    let baseFont: NSFont
    let baseAttributes: [NSAttributedString.Key: Any]
    let backgroundColor: NSColor
    let caretColor: NSColor
    let selectionAttributes: [NSAttributedString.Key: Any]
    private let codePalette: [String: String]
    /// Heading sizes in themes are written for a 14 pt editor font.
    private let sizeScale: CGFloat
    private var tokenCache: [HighlightToken: TokenAttributes] = [:]

    struct TokenAttributes {
        let foreground: NSColor?
        let background: NSColor?
        let isBold: Bool
        let isItalic: Bool
        let fontSize: CGFloat?
        let isStrikethrough: Bool
    }

    init(definition: ThemeDefinition, fontName: String, fontSize: Double, lineHeight: Double) {
        style = definition.styleTheme
        isDark = definition.appearance == .dark
        codePalette = definition.code
        let size = CGFloat(fontSize)
        sizeScale = size / 14
        baseFont = (fontName.isEmpty ? nil : NSFont(name: fontName, size: size))
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = CGFloat(lineHeight)
        let foreground = style.editor.foreground.map(NSColor.init) ?? .textColor
        baseAttributes = [.font: baseFont, .foregroundColor: foreground, .paragraphStyle: paragraph]
        backgroundColor = style.editor.background.map(NSColor.init) ?? .textBackgroundColor
        caretColor = style.editor.caret.map(NSColor.init) ?? foreground
        var selection: [NSAttributedString.Key: Any] = [
            .backgroundColor: style.selection?.background.map(NSColor.init) ?? NSColor.selectedTextBackgroundColor,
        ]
        if let selectedForeground = style.selection?.foreground {
            selection[.foregroundColor] = NSColor(selectedForeground)
        }
        selectionAttributes = selection
    }

    func attributes(for token: HighlightToken) -> TokenAttributes {
        if let cached = tokenCache[token] { return cached }
        let tokenStyle = style.style(for: token)
        let attributes = TokenAttributes(
            foreground: tokenStyle?.foreground.map(NSColor.init),
            background: tokenStyle?.background.map(NSColor.init),
            isBold: tokenStyle?.isBold ?? (token == .strong),
            isItalic: tokenStyle?.isItalic ?? (token == .emphasis),
            fontSize: tokenStyle?.fontSize.map { CGFloat($0) * sizeScale },
            isStrikethrough: token == .strikethrough
        )
        tokenCache[token] = attributes
        return attributes
    }

    // MARK: Code

    private var codeColorCache: [String: NSColor] = [:]

    /// Colour for a highlight.js scope, from the theme's `code` palette (`keyword.control` falls
    /// back to `keyword`).
    func codeColor(for scope: String) -> NSColor? {
        if let cached = codeColorCache[scope] { return cached }
        let base = String(scope.split(separator: ".").first ?? "")
        guard let hex = codePalette[scope] ?? codePalette[base], let parsed = StyleTheme.Color(hex: hex) else {
            return nil
        }
        let color = NSColor(parsed)
        codeColorCache[scope] = color
        return color
    }

    // MARK: Loading

    /// The chosen light or dark theme for the appearance, with the user's font.
    static func forAppearance(_ appearance: NSAppearance) -> EditorTheme {
        ThemeStore.shared.editorTheme(for: appearance)
    }
}

private extension NSColor {
    convenience init(_ color: StyleTheme.Color) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}
