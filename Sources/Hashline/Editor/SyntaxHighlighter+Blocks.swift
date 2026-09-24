import AppKit
import HashlineCore

/// Front matter (as YAML) and fenced code blocks (highlight.js), both coloured asynchronously.
extension SyntaxHighlighter {
    // MARK: Front matter

    /// CommonMark reads front matter as a thematic break and a setext heading; restyle it as YAML.
    func styleFrontMatter(in text: NSString) {
        guard let frontMatter = FrontMatter.detect(in: text), NSMaxRange(frontMatter.range) <= storage.length else {
            frontMatterEnd = 0
            return
        }
        frontMatterEnd = NSMaxRange(frontMatter.range)
        storage.setAttributes(theme.baseAttributes, range: frontMatter.range)
        if let comment = theme.attributes(for: .comment).foreground {
            storage.addAttribute(.foregroundColor, value: comment, range: frontMatter.range)
        }
        let yaml = text.substring(with: frontMatter.contentRange)
        let location = frontMatter.contentRange.location
        CodeHighlighter.shared.tokens(code: yaml, language: "yaml") { [weak self] tokens in
            guard let self, let tokens, let current = FrontMatter.detect(in: self.storage.mutableString),
                  current.contentRange == frontMatter.contentRange,
                  self.storage.mutableString.substring(with: current.contentRange) == yaml else { return }
            self.applyCode(tokens, at: location, limit: NSMaxRange(frontMatter.contentRange))
        }
    }

    // MARK: Code blocks

    /// Colours a fenced code block asynchronously (highlight.js runs off the main thread, ADR 0008).
    /// The result is dropped if the block was edited meanwhile (its id changes on every reparse).
    func requestCodeHighlight(for block: MarkdownBlock, in text: NSString) {
        guard let fenced = block.fencedCode(in: text), !pendingCode.contains(block.id) else { return }
        let id = block.id
        pendingCode.insert(id)
        // ```math is TeX; highlight.js knows it as LaTeX.
        let language = fenced.language == "math" ? "latex" : fenced.language
        CodeHighlighter.shared.tokens(code: fenced.code, language: language) { [weak self] tokens in
            guard let self else { return }
            self.pendingCode.remove(id)
            guard let tokens, let blockMap = self.blockMap,
                  let index = blockMap.blockIndex(at: fenced.range.location),
                  blockMap.blocks[index].id == id else { return }
            self.applyCode(tokens, at: fenced.range.location, limit: NSMaxRange(fenced.range))
        }
    }

    func applyCode(_ tokens: [CodeToken], at location: Int, limit: Int) {
        guard limit <= storage.length else { return }
        storage.beginEditing()
        for token in tokens {
            let range = NSRange(location: location + token.range.location, length: token.range.length)
            guard NSMaxRange(range) <= limit, let color = theme.codeColor(for: token.scope) else { continue }
            storage.addAttribute(.foregroundColor, value: color, range: range)
        }
        storage.endEditing()
    }
}
