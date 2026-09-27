import AppKit
import HashlineCore

extension LibraryStore {
    /// Asks for a name and creates an empty folder in the browsed library folder.
    func createFolder() {
        guard let parent = targetFolder else { return chooseFolder() }
        let alert = NSAlert()
        alert.messageText = String(localized: "New Folder")
        alert.informativeText = String(localized: "Enter a name for the new folder.")
        let field = NSTextField(string: String(localized: "Untitled Folder"))
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Create"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let target = try LibraryIndex.newFolderURL(named: field.stringValue, in: parent)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        } catch let error as LibraryIndex.RenameError {
            showFolderNameError(error, name: field.stringValue)
        } catch {
            NSAlert(error: error).runModal()
        }
        rescan()
    }

    /// Moves a library folder with everything in it to the Trash, after a confirmation. Documents
    /// open from it are saved and closed first; if saving fails, nothing is moved.
    func moveFolderToTrash(_ path: String) {
        guard let folder, !path.isEmpty else { return }
        let url = folder.appendingPathComponent(path, isDirectory: true)
        // Never the library itself, nothing outside it and no symbolic link (its target would go).
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard LibraryIndex.isStrictlyInside(url, root: folder), values?.isDirectory == true,
              values?.isSymbolicLink != true else { return }
        guard confirmTrash(of: path) else { return }
        Task { await trashClosingDocuments(url) }
    }

    private func confirmTrash(of path: String) -> Bool {
        let count = items.filter { $0.relativePath.hasPrefix(path + "/") }.count
        let alert = NSAlert()
        alert.alertStyle = .warning
        let name = (path as NSString).lastPathComponent
        alert.messageText = String(localized: "Move the folder “\(name)” to the Trash?")
        alert.informativeText = count == 0
            ? String(localized: "The folder contains no documents. You can restore it from the Trash.")
            : String(localized: """
                The folder and everything in it, including \(count) documents, will be moved to the Trash. \
                You can restore it from there.
                """)
        let trash = alert.addButton(withTitle: String(localized: "Move to Trash"))
        trash.hasDestructiveAction = true
        let cancel = alert.addButton(withTitle: String(localized: "Cancel"))
        // Return cancels: deleting a folder takes a deliberate click.
        trash.keyEquivalent = ""
        cancel.keyEquivalent = "\r"
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Saves and closes every open document inside `url`, then moves `url` to the Trash. Waits for
    /// each save, so no autosave can write into the folder after it has moved.
    private func trashClosingDocuments(_ url: URL) async {
        let root = url.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let open = NSDocumentController.shared.documents.filter { document in
            guard let fileURL = document.fileURL else { return false }
            return fileURL.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root)
        }
        for document in open {
            let error: Error? = await withCheckedContinuation { continuation in
                document.autosave(withImplicitCancellability: false) { continuation.resume(returning: $0) }
            }
            if let error {
                let message = error.localizedDescription
                Performance.logger.error("Saving before folder trash failed: \(message, privacy: .public)")
                NSAlert(error: error).runModal()
                return
            }
        }
        open.forEach { $0.close() }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            Performance.logger.error("Folder trash failed: \(error.localizedDescription, privacy: .public)")
            NSAlert(error: error).runModal()
        }
        rescan()
    }

    private func showFolderNameError(_ error: LibraryIndex.RenameError, name: String) {
        let alert = NSAlert()
        switch error {
        case .empty: alert.messageText = String(localized: "The name cannot be empty.")
        case .invalidCharacters:
            alert.messageText = String(localized: "The name cannot contain “/” or “:” or start with a dot.")
        case .exists: alert.messageText = String(localized: "A folder named “\(name)” already exists.")
        }
        alert.runModal()
    }
}
