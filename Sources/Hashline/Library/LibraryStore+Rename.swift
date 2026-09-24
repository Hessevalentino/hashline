import AppKit
import HashlineCore

extension LibraryStore {
    /// Asks for a new name and renames the document in place. An open document is moved through
    /// its NSDocument, so its window, autosave and versions follow the new file.
    func rename(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Document")
        alert.informativeText = String(localized: "Enter a new name for “\(url.lastPathComponent)”.")
        let field = NSTextField(string: url.deletingPathExtension().lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Rename"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let target: URL
        do {
            guard let renamed = try LibraryIndex.renamedURL(url, to: field.stringValue) else { return }
            target = renamed
        } catch {
            return showRenameError(error, name: field.stringValue)
        }
        let open = NSDocumentController.shared.documents.first {
            $0.fileURL?.standardizedFileURL == url.standardizedFileURL
        }
        if let open {
            open.move(to: target) { error in
                MainActor.assumeIsolated {
                    if let error { NSAlert(error: error).runModal() }
                    self.rescan()
                }
            }
            return
        }
        do {
            try FileManager.default.moveItem(at: url, to: target)
        } catch {
            NSAlert(error: error).runModal()
        }
        rescan()
    }

    private func showRenameError(_ error: LibraryIndex.RenameError, name: String) {
        let alert = NSAlert()
        switch error {
        case .empty: alert.messageText = String(localized: "The name cannot be empty.")
        case .invalidCharacters:
            alert.messageText = String(localized: "The name cannot contain “/” or “:” or start with a dot.")
        case .exists: alert.messageText = String(localized: "A document named “\(name)” already exists.")
        }
        alert.runModal()
    }
}
