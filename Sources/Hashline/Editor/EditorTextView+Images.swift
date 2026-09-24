import AppKit
import HashlineCore

/// Dropping and pasting images, optional upload, and document-wide image actions.
extension EditorTextView {
    var documentURL: URL? { window?.representedURL }

    // MARK: Drop and paste

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard ImageInsertion.hasImages(sender.draggingPasteboard) else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        let location = characterIndexForInsertion(at: point)
        setSelectedRange(NSRange(location: location, length: 0))
        return insertImages(from: sender.draggingPasteboard)
    }

    /// Returns false when nothing was inserted (unsaved document, access refused).
    @discardableResult
    func insertImages(from pasteboard: NSPasteboard) -> Bool {
        guard let markdown = ImageInsertion.insertMarkdown(from: pasteboard, documentURL: documentURL,
                                                           lineEnding: lineEnding.rawValue, window: window)
        else { return false }
        let selection = selectedRange()
        let end = NSRange(location: selection.location + (markdown as NSString).length, length: 0)
        breakUndoCoalescing()
        apply(TextEdit(range: selection, replacement: markdown, selection: end), actionName: "Insert Image")
        uploadInsertedImages(markdown)
        return true
    }

    /// With an uploader configured, replaces the local links just inserted by the uploaded URLs.
    private func uploadInsertedImages(_ markdown: String) {
        guard let configuration = ImageUploader.configuration, let documentURL else { return }
        let links = markdown.split(separator: "\n").compactMap { line -> (String, URL)? in
            guard let open = line.range(of: "]("), line.hasSuffix(")") else { return nil }
            let relative = String(line[open.upperBound..<line.index(before: line.endIndex)])
            guard case .local(let file) = ImageLinks.resolve(relative, base: documentURL.deletingLastPathComponent())
            else { return nil }
            return (relative, file)
        }
        for (relative, file) in links {
            Task { @MainActor [weak self] in
                do {
                    let url = try await ImageUploader.upload(file, with: configuration)
                    self?.replaceImageSource(relative, with: url.absoluteString)
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
        }
    }

    /// Replaces every `(source)` image reference with `(replacement)` as one undo step.
    func replaceImageSource(_ source: String, with replacement: String) {
        replaceImageSources([source: replacement], actionName: "Upload Image")
    }

    func replaceImageSources(_ mapping: [String: String], actionName: LocalizedStringResource) {
        guard let storage = textStorage, !mapping.isEmpty else { return }
        let text = storage.mutableString
        let blocks = BlockMap(text: text as String).blocks
        let edits = ImageLinks.references(in: blocks, text: text)
            .filter { mapping[$0.source] != nil }
            .sorted { $0.sourceRange.location > $1.sourceRange.location }
            .compactMap { reference in
                mapping[reference.source].map {
                    TextEdit(range: reference.sourceRange, replacement: $0, selection: selectedRange())
                }
            }
        guard !edits.isEmpty else { return }
        run(name: actionName) { _, _ in edits }
    }

    // MARK: Document-wide actions

    /// Copies local images outside the assets folder into it and relinks them.
    @objc func copyImagesToAssets(_ sender: Any?) {
        guard let documentURL, let storage = textStorage else { return saveFirst() }
        let perDocument = UserDefaults.standard.bool(forKey: ImageSettings.perDocumentFolderKey)
        let assets = ImageLinks.assetsFolder(for: documentURL, perDocument: perDocument)
        guard ImageInsertion.ensureAccess(to: assets, documentURL: documentURL) else { return }
        let base = ImageLinks.base(documentURL: documentURL, text: storage.mutableString)
        var mapping: [String: String] = [:]
        for reference in ImageLinks.references(in: BlockMap(text: storage.string).blocks, text: storage.mutableString) {
            guard mapping[reference.source] == nil,
                  case .local(let file) = ImageLinks.resolve(reference.source, base: base),
                  !file.path.hasPrefix(assets.path + "/"),
                  FileManager.default.fileExists(atPath: file.path) else { continue }
            guard FolderAccess.shared.canAccess(file) else { continue }
            do {
                try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
                let copied = try LibraryIndex.importFiles([file], into: assets)
                if let target = copied.first {
                    mapping[reference.source] = ImageLinks.relativeLink(from: documentURL, to: target)
                }
            } catch {
                NSAlert(error: error).runModal()
                return
            }
        }
        replaceImageSources(mapping, actionName: "Copy Images")
    }

    /// Downloads remote images into the assets folder and relinks them.
    @objc func downloadRemoteImages(_ sender: Any?) {
        guard let documentURL, let storage = textStorage else { return saveFirst() }
        let perDocument = UserDefaults.standard.bool(forKey: ImageSettings.perDocumentFolderKey)
        let assets = ImageLinks.assetsFolder(for: documentURL, perDocument: perDocument)
        guard ImageInsertion.ensureAccess(to: assets, documentURL: documentURL) else { return }
        let references = ImageLinks.references(in: BlockMap(text: storage.string).blocks, text: storage.mutableString)
        let remote = Set(references.compactMap { reference -> String? in
            if case .remote = ImageLinks.resolve(reference.source, base: nil) { return reference.source }
            return nil
        })
        guard !remote.isEmpty else { return }
        Task { @MainActor [weak self] in
            var mapping: [String: String] = [:]
            try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
            for source in remote {
                guard let url = URL(string: source),
                      let (data, response) = try? await URLSession.shared.data(from: url),
                      (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { continue }
                let name = url.lastPathComponent.isEmpty ? "image.png" : url.lastPathComponent
                let target = LibraryIndex.uniqueURL(for: name, in: assets)
                guard (try? data.write(to: target)) != nil else { continue }
                mapping[source] = ImageLinks.relativeLink(from: documentURL, to: target)
            }
            self?.replaceImageSources(mapping, actionName: "Download Images")
        }
    }

    private func saveFirst() {
        let alert = NSAlert()
        alert.messageText = "Save the document first"
        alert.informativeText = "Images are stored next to the document, so it needs a place on disk."
        alert.runModal()
    }
}
