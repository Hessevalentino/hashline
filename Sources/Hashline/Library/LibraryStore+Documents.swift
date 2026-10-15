import AppKit
import HashlineCore
import UniformTypeIdentifiers

extension LibraryStore {
    /// Moves documents to the Trash (recoverable there, as in Finder). Windows showing them close
    /// first, after saving, so no editor keeps writing to a trashed file.
    func moveToTrash(_ urls: [URL]) {
        let targets = Set(urls.map(\.standardizedFileURL))
        guard !targets.isEmpty else { return }
        for document in NSDocumentController.shared.documents {
            guard let url = document.fileURL?.standardizedFileURL, targets.contains(url) else { continue }
            document.autosave(withImplicitCancellability: false) { _ in }
            document.close()
        }
        var failures: [String] = []
        for url in targets {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                failures.append(url.lastPathComponent)
                Performance.logger.error("Trash failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        rescan()
        if !failures.isEmpty {
            let alert = NSAlert()
            alert.messageText = String(localized: "Some documents could not be moved to the Trash.")
            alert.informativeText = failures.sorted().joined(separator: "\n")
            alert.runModal()
        }
    }

    func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Opens a library document as a tab of `window` (or brings it forward if already open).
    func openDocument(_ item: LibraryDocument, besides window: NSWindow?) {
        openDocument(at: item.url, besides: window)
    }

    func openDocument(at url: URL, besides window: NSWindow?) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
            if let error {
                let path = url.lastPathComponent
                Performance.logger.error(
                    "Opening \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
                return
            }
            MainActor.assumeIsolated {
                guard let window, let newWindow = document?.windowControllers.first?.window, newWindow !== window,
                      !(window.tabbedWindows ?? []).contains(newWindow) else { return }
                window.addTabbedWindow(newWindow, ordered: .above)
                newWindow.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Creates `Untitled.md` in the browsed library folder and opens it; no save panel.
    func createDocument(besides window: NSWindow?) {
        guard let folder = targetFolder else { return addFolders() }
        let url = LibraryIndex.uniqueURL(for: "Untitled.md", in: folder)
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else { return }
        rescan()
        let relativePath = (currentFolder.isEmpty ? roots.first?.name ?? "" : currentFolder) + "/"
            + url.lastPathComponent
        let item = LibraryDocument(url: url, relativePath: relativePath, title: "Untitled",
                               modified: .now, snippet: "")
        openDocument(item, besides: window)
    }

    func importFiles() {
        guard let folder = targetFolder else { return addFolders() }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(importedAs: "net.daringfireball.markdown"), .plainText]
        panel.prompt = String(localized: "Add to Library")
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls, into: folder)
    }

    func importFiles(_ urls: [URL]) {
        guard let folder = targetFolder else { return }
        let documents = urls.filter {
            LibraryIndex.extensions.contains($0.pathExtension.lowercased()) || $0.pathExtension.lowercased() == "txt"
        }
        importFiles(documents, into: folder)
    }

    private func importFiles(_ urls: [URL], into folder: URL) {
        do {
            _ = try LibraryIndex.importFiles(urls, into: folder)
        } catch {
            NSAlert(error: error).runModal()
        }
        rescan()
    }
}
