import Foundation

/// Converts pasted HTML (browsers, Word, mail) to Markdown. Uses the system HTML parser
/// (`XMLDocument` with tidy), no third-party dependency. Unknown elements keep their text;
/// scripts, styles and comments are dropped.
public enum HTMLToMarkdown {
    public static func convert(_ html: String) -> String? {
        guard let document = try? XMLDocument(xmlString: html, options: [.documentTidyHTML]) else { return nil }
        let body = (try? document.nodes(forXPath: "//body").first) ?? document.rootElement()
        guard let body else { return nil }
        var converter = Converter()
        converter.blockChildren(of: body)
        let markdown = converter.output
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return markdown.isEmpty ? nil : markdown
    }
}

private struct Converter {
    var output = ""
    private var listStack: [(ordered: Bool, index: Int)] = []
    private var quoteDepth = 0

    private static let blockElements: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "pre", "hr",
        "table", "section", "article", "header", "footer", "main", "figure",
    ]
    private static let ignored: Set<String> = ["script", "style", "head", "title", "meta", "link", "noscript"]

    // MARK: Blocks

    mutating func blockChildren(of node: XMLNode) {
        var inline = ""
        for child in node.children ?? [] {
            if isBlock(child) {
                flushParagraph(&inline)
                block(child)
            } else {
                inline += inlineMarkdown(child)
            }
        }
        flushParagraph(&inline)
    }

    private mutating func flushParagraph(_ inline: inout String) {
        let text = collapse(inline)
        if !text.isEmpty { paragraph(text) }
        inline = ""
    }

    // One case per HTML element reads best as a single switch.
    // swiftlint:disable:next cyclomatic_complexity
    private mutating func block(_ node: XMLNode) {
        guard let element = node as? XMLElement, let name = element.name?.lowercased() else { return }
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(name.dropFirst())) ?? 1
            let text = collapse(inlineChildren(of: element))
            if !text.isEmpty { paragraph(String(repeating: "#", count: level) + " " + text) }
        case "p", "section", "article", "header", "footer", "main", "figure", "div":
            blockChildren(of: element)
        case "hr":
            paragraph("---")
        case "pre":
            let code = element.stringValue ?? ""
            let language = languageClass(of: element)
            paragraph("```\(language)\n" + code.trimmingCharacters(in: .newlines) + "\n```")
        case "blockquote":
            quoteDepth += 1
            blockChildren(of: element)
            quoteDepth -= 1
        case "ul", "ol":
            listStack.append((name == "ol", 1))
            for child in element.children ?? [] where (child as? XMLElement)?.name?.lowercased() == "li" {
                listItem(child)
            }
            listStack.removeLast()
            if listStack.isEmpty { output += "\n" }
        case "li":
            listItem(element)
        case "table":
            table(element)
        default:
            blockChildren(of: element)
        }
    }

    private mutating func listItem(_ node: XMLNode) {
        guard let current = listStack.last else { return blockChildren(of: node) }
        let marker = current.ordered ? "\(current.index)." : "-"
        listStack[listStack.count - 1].index += 1
        let indent = String(repeating: "  ", count: listStack.count - 1)
        var inline = ""
        var nested: [XMLNode] = []
        for child in node.children ?? [] {
            if let name = (child as? XMLElement)?.name?.lowercased(), name == "ul" || name == "ol" {
                nested.append(child)
            } else if isBlock(child) {
                inline += " " + inlineChildren(of: child)
            } else {
                inline += inlineMarkdown(child)
            }
        }
        output += quotePrefix + indent + marker + " " + collapse(inline) + "\n"
        for list in nested { block(list) }
    }

    private mutating func table(_ element: XMLElement) {
        let rows = (try? element.nodes(forXPath: ".//tr")) ?? []
        let cells = rows.map { row in
            (row.children ?? []).filter { ["td", "th"].contains(($0 as? XMLElement)?.name?.lowercased() ?? "") }
                .map { collapse(inlineChildren(of: $0)).replacingOccurrences(of: "|", with: "\\|") }
        }.filter { !$0.isEmpty }
        guard let header = cells.first else { return }
        let columns = cells.map(\.count).max() ?? header.count
        func row(_ values: [String]) -> String {
            "| " + (values + Array(repeating: "", count: columns - values.count)).joined(separator: " | ") + " |"
        }
        var lines = [row(header), "|" + Array(repeating: "---|", count: columns).joined()]
        lines += cells.dropFirst().map(row)
        paragraph(lines.joined(separator: "\n"))
    }

    private mutating func paragraph(_ text: String) {
        let prefixed = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { quotePrefix + $0 }.joined(separator: "\n")
        if !output.isEmpty && !output.hasSuffix("\n\n") { output += output.hasSuffix("\n") ? "\n" : "\n\n" }
        output += prefixed + "\n\n"
    }

    private var quotePrefix: String { String(repeating: "> ", count: quoteDepth) }

    // MARK: Inline

    private func inlineChildren(of node: XMLNode) -> String {
        (node.children ?? []).map(inlineMarkdown).joined()
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func inlineMarkdown(_ node: XMLNode) -> String {
        switch node.kind {
        case .text: return escape(node.stringValue ?? "")
        case .element: break
        default: return ""
        }
        guard let element = node as? XMLElement, let name = element.name?.lowercased() else { return "" }
        if Self.ignored.contains(name) { return "" }
        let inner = inlineChildren(of: element)
        switch name {
        case "strong", "b": return wrap(inner, "**")
        case "em", "i": return wrap(inner, "*")
        case "u", "ins": return wrap(inner, "<u>", "</u>")
        case "s", "del", "strike": return wrap(inner, "~~")
        case "code", "kbd", "samp":
            let code = element.stringValue ?? ""
            return code.contains("`") ? "`` \(code) ``" : "`\(code)`"
        case "br": return "  \n"
        case "a":
            guard let href = element.attribute(forName: "href")?.stringValue, !href.hasPrefix("javascript:") else {
                return inner
            }
            return inner.isEmpty ? "<\(href)>" : "[\(inner)](\(href))"
        case "img":
            let source = element.attribute(forName: "src")?.stringValue ?? ""
            let alt = element.attribute(forName: "alt")?.stringValue ?? ""
            return source.isEmpty ? "" : "![\(escape(alt))](\(source))"
        default:
            // A block nested in inline context contributes its text on its own line.
            return isBlock(element) ? " " + inner + " " : inner
        }
    }

    private func wrap(_ text: String, _ open: String, _ close: String? = nil) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return text }
        let leading = text.hasPrefix(" ") ? " " : ""
        let trailing = text.hasSuffix(" ") ? " " : ""
        return leading + open + trimmed + (close ?? open) + trailing
    }

    private func isBlock(_ node: XMLNode) -> Bool {
        guard let name = (node as? XMLElement)?.name?.lowercased() else { return false }
        return Self.blockElements.contains(name)
    }

    private func languageClass(of pre: XMLElement) -> String {
        let code = (pre.children ?? []).first { ($0 as? XMLElement)?.name?.lowercased() == "code" } as? XMLElement
        let classes = (code ?? pre).attribute(forName: "class")?.stringValue ?? ""
        return classes.split(separator: " ").first { $0.hasPrefix("language-") }
            .map { String($0.dropFirst("language-".count)) } ?? ""
    }

    /// HTML whitespace rules: runs of whitespace are one space, except explicit line breaks.
    private func collapse(_ text: String) -> String {
        text.components(separatedBy: "  \n").map {
            $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }.joined(separator: "  \n")
    }

    /// Escapes characters that would otherwise start Markdown formatting.
    private func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            if "*_`[]<\\".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}
