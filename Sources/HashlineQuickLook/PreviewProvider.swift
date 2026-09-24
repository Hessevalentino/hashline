import Foundation
import HashlineCore
import OSLog
import QuickLookUI
import UniformTypeIdentifiers

/// Quick Look for Markdown files in Finder (space bar): the same renderer as Hashline's preview,
/// with the built-in light and dark themes. No JavaScript: Mermaid diagrams stay as code.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private static let logger = Logger(subsystem: "cz.hashline.Hashline.QuickLook", category: "preview")
    /// Longer files show their beginning; Quick Look is for a glance, not for 10 MB.
    private static let characterLimit = 200_000

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let started = ContinuousClock.now
        let data = try Data(contentsOf: request.fileURL, options: .mappedIfSafe)
        var text = try TextFileCodec.decode(data).text as NSString
        var truncated = false
        if text.length > Self.characterLimit {
            let cut = text.lineRange(for: NSRange(location: Self.characterLimit, length: 0)).location
            text = text.substring(to: cut) as NSString
            truncated = true
        }
        let blocks = BlockMap(text: text as String).blocks
        var options = HTMLRenderer.Options.export
        options.mermaid = false
        var body = ExportDocument.body(blocks: blocks, text: text, options: options)
        if truncated {
            body += "<p class=\"hashline-truncated\">" + String(localized: "Open the document to see the rest.")
                + "</p>\n"
        }
        let title = ExportDocument.title(text: text, blocks: blocks,
                                         fallback: request.fileURL.deletingPathExtension().lastPathComponent)
        let stylesheet = Self.stylesheet(katex: body.contains("class=\"katex"))
        let html = ExportDocument.html(body: body, title: title, stylesheet: stylesheet)
        let milliseconds = Double(started.duration(to: .now).components.attoseconds) / 1e15
        Self.logger.notice(
            "Quick Look preview: \(text.length) characters in \(milliseconds, format: .fixed(precision: 0)) ms")
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 820, height: 1_000)) { reply in
            reply.stringEncoding = .utf8
            reply.title = title
            return Data(html.utf8)
        }
    }

    private static func stylesheet(katex: Bool) -> String {
        func resource(_ path: String) -> String {
            Bundle.main.url(forResource: path, withExtension: nil)
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        }
        var sheet = "@media (prefers-color-scheme: light) {\n" + resource("Themes/Paper.hashlinetheme/theme.css")
            + "\n}\n@media (prefers-color-scheme: dark) {\n"
            + resource("Themes/Tomorrow Night.hashlinetheme/theme.css") + "\n}\n"
        sheet += """
            pre code.hljs { background: transparent; padding: 0; }
            .math-display { overflow-x: auto; margin: 1em 0; }
            .front-matter { display: none; }
            .hashline-truncated { opacity: 0.6; font-style: italic; }
            .task-list-item { list-style: none; }
            .task-list-item > input[type=checkbox] { margin: 0 0.4em 0 -1.35em; vertical-align: middle; }
            """
        if katex { sheet += resource("katex-inline.css") }
        return sheet
    }
}
