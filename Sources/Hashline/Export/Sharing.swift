import AppKit
import HashlineCore

/// Sharing (toolbar, File ▸ Share…, AirDrop) always hands over a `.md` file with the text as it is
/// in the editor, unsaved edits included, named like the document.
@MainActor
enum Sharing {
    /// The previous copy, removed when the next one is made (services read it asynchronously).
    private static var lastCopy: URL?

    static func markdownFile(for session: EditorSession) -> URL? {
        let text = session.document.textStorage.string
        let name = fileName(for: session, text: text)
        let fileManager = FileManager.default
        if let lastCopy { try? fileManager.removeItem(at: lastCopy) }
        let folder = fileManager.temporaryDirectory.appendingPathComponent("Share-\(UUID().uuidString)")
        let url = folder.appendingPathComponent(name)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            Performance.logger.error("Share copy failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        lastCopy = folder
        return url
    }

    /// The document's file name; for an untitled document its first heading, else “Untitled.md”.
    private static func fileName(for session: EditorSession, text: String) -> String {
        if let url = session.documentURL {
            let base = url.deletingPathExtension().lastPathComponent
            let isMarkdown = LibraryIndex.extensions.contains(url.pathExtension.lowercased())
            return isMarkdown ? url.lastPathComponent : base + ".md"
        }
        let title = session.highlighter?.blockMap.map {
            ExportDocument.title(text: text as NSString, blocks: $0.blocks, fallback: "")
        } ?? ""
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? String(localized: "Untitled") : String(cleaned.prefix(80))) + ".md"
    }

    /// File ▸ Share…: the system share menu under the toolbar.
    static func showPicker(for session: EditorSession) {
        guard let window = session.textView?.window ?? NSApp.keyWindow,
              let view = window.contentView, let url = markdownFile(for: session) else { return }
        let picker = NSSharingServicePicker(items: [url])
        let top = view.isFlipped ? view.bounds.minY : view.bounds.maxY - 1
        let anchor = NSRect(x: view.bounds.maxX - 120, y: top, width: 1, height: 1)
        picker.show(relativeTo: anchor, of: view, preferredEdge: view.isFlipped ? .maxY : .minY)
    }

    /// File ▸ Send with AirDrop…
    static func sendWithAirDrop(_ session: EditorSession) {
        guard let url = markdownFile(for: session) else { return }
        sendWithAirDrop([url])
    }

    static func sendWithAirDrop(_ urls: [URL]) {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            NSSound.beep()
            return
        }
        service.perform(withItems: urls)
    }
}
