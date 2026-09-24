import Foundation
import Markdown

/// Markdown → readable plain text ("Copy as Plain Text"): markers removed, structure kept
/// with blank lines between blocks, bullets for lists and tabs between table cells.
public enum PlainTextRenderer {
    public static func plainText(from markdown: String) -> String {
        let document = Document(parsing: markdown, options: [.disableSmartOpts])
        return document.children.map { block($0, indent: "") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    public static func html(from markdown: String) -> String {
        HTMLRenderer.body(for: BlockMap(text: markdown).blocks)
    }

    private static func block(_ node: Markup, indent: String) -> String {
        switch node {
        case let code as CodeBlock:
            return code.code.trimmingCharacters(in: .newlines)
        case let list as UnorderedList:
            return list.listItems.map { item(bullet: "•", $0, indent: indent) }.joined(separator: "\n")
        case let list as OrderedList:
            return list.listItems.enumerated().map { index, item in
                self.item(bullet: "\(Int(list.startIndex) + index).", item, indent: indent)
            }.joined(separator: "\n")
        case let quote as BlockQuote:
            return quote.children.map { block($0, indent: indent) }.joined(separator: "\n\n")
        case let table as Table:
            let head = table.head.cells.map { inline($0) }.joined(separator: "\t")
            let rows = table.body.rows.map { $0.cells.map { inline($0) }.joined(separator: "\t") }
            return ([head] + rows).joined(separator: "\n")
        case is ThematicBreak:
            return ""
        case let html as HTMLBlock:
            return html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return inline(node)
        }
    }

    private static func item(bullet: String, _ item: ListItem, indent: String) -> String {
        let checkbox = item.checkbox.map { $0 == .checked ? "☑ " : "☐ " } ?? ""
        let parts = item.children.map { child -> String in
            if child is UnorderedList || child is OrderedList { return block(child, indent: indent + "    ") }
            return block(child, indent: indent)
        }
        guard let first = parts.first else { return indent + bullet }
        return ([indent + bullet + " " + checkbox + first] + parts.dropFirst()).joined(separator: "\n")
    }

    private static func inline(_ node: Markup) -> String {
        switch node {
        case let text as Text: return text.string
        case is SoftBreak: return " "
        case is LineBreak: return "\n"
        case let code as InlineCode: return code.code
        case let image as Image: return image.plainText
        case let html as InlineHTML: return html.rawHTML.hasPrefix("<") ? "" : html.rawHTML
        default: return node.children.map(inline).joined()
        }
    }
}
