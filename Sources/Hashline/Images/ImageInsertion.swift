import AppKit
import HashlineCore
import UniformTypeIdentifiers

enum ImageSettings {
    static let perDocumentFolderKey = "imagesPerDocumentFolder"
    static let uploaderEnabledKey = "imageUploaderEnabled"
    /// Security-scoped bookmark of the upload program the user chose (the sandbox runs only files
    /// the app may read, so a typed path would silently fail).
    static let uploaderBookmarkKey = "imageUploaderBookmark"
    static let uploaderArgumentsKey = "imageUploaderArguments"
    /// Remote images in the preview reveal to their server that the document was opened.
    static let loadsRemoteImagesKey = "loadsRemoteImages"

    static var loadsRemoteImages: Bool {
        let defaults = UserDefaults.standard
        // bool(forKey:) also reads "NO" from launch arguments, which `as? Bool` would not.
        return defaults.object(forKey: loadsRemoteImagesKey) == nil || defaults.bool(forKey: loadsRemoteImagesKey)
    }
}

/// Images dropped or pasted into the editor: copied next to the document and linked relatively.
@MainActor
enum ImageInsertion {
    /// Whether the pasteboard carries images (files or image data) rather than text.
    static func hasImages(_ pasteboard: NSPasteboard) -> Bool {
        !imageFiles(pasteboard).isEmpty
            || (pasteboard.string(forType: .string) == nil && pasteboard.canReadItem(withDataConformingToTypes:
                [UTType.png.identifier, UTType.tiff.identifier, UTType.jpeg.identifier]))
    }

    static func imageFiles(_ pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        return pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }

    /// Copies the pasteboard's images into the assets folder and returns Markdown links, one per line.
    /// Returns nil (after telling the user why) when the document is unsaved or access is refused.
    static func insertMarkdown(from pasteboard: NSPasteboard, documentURL: URL?, lineEnding: String,
                               window: NSWindow?) -> String? {
        guard let documentURL else {
            Performance.logger.notice("Image insertion: document not saved")
            let alert = NSAlert()
            alert.messageText = String(localized: "Save the document first")
            alert.informativeText = String(
                localized: "Images are copied next to the document, so it needs a place on disk.")
            alert.runModal()
            return nil
        }
        let perDocument = UserDefaults.standard.bool(forKey: ImageSettings.perDocumentFolderKey)
        let assets = ImageLinks.assetsFolder(for: documentURL, perDocument: perDocument)
        guard ensureAccess(to: assets, documentURL: documentURL) else {
            Performance.logger.notice("Image insertion: no access to \(assets.path, privacy: .public)")
            return nil
        }

        var copied: [URL] = []
        do {
            try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
            let files = imageFiles(pasteboard)
            if files.isEmpty, let png = pngData(from: pasteboard) {
                let name = "image-\(Self.timestamp()).png"
                let target = LibraryIndex.uniqueURL(for: name, in: assets)
                try png.write(to: target)
                copied.append(target)
            } else {
                copied = try LibraryIndex.importFiles(files, into: assets)
            }
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
        let links = copied.map { file in
            let name = file.deletingPathExtension().lastPathComponent
            return "![\(name)](\(ImageLinks.relativeLink(from: documentURL, to: file)))"
        }
        return links.joined(separator: lineEnding)
    }

    /// Writing next to the document needs its folder (sandbox); ask once, remembered afterwards.
    static func ensureAccess(to assets: URL, documentURL: URL) -> Bool {
        let access = FolderAccess.shared
        if access.canAccess(assets) { return true }
        let folder = documentURL.deletingLastPathComponent()
        let message = "Hashline stores images in “\(assets.lastPathComponent)” next to your document. "
            + "Allow access to this folder."
        guard let granted = access.requestAccess(to: folder, message: message) else { return false }
        return FolderAccess.isAccessible(assets, roots: [granted]) || access.canAccess(assets)
    }

    private static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        let jpeg = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        guard let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: jpeg),
              let bitmap = NSBitmapImageRep(data: data) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }
}

/// Uploads an image with a user-configured command (PicGo, uPic, own script). The command gets the
/// file path as a separate argument, never through a shell, and must print the URL.
enum ImageUploader {
    struct Configuration: Sendable {
        let executable: URL
        let arguments: [String]
    }

    /// Only when switched on and a program was chosen.
    @MainActor
    static var configuration: Configuration? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: ImageSettings.uploaderEnabledKey), let executable = chosenProgram else {
            return nil
        }
        let template = defaults.string(forKey: ImageSettings.uploaderArgumentsKey) ?? "{file}"
        return Configuration(executable: executable, arguments: template.split(separator: " ").map(String.init))
    }

    /// The program chosen in Settings, with sandbox access started.
    @MainActor
    static var chosenProgram: URL? {
        guard let data = UserDefaults.standard.data(forKey: ImageSettings.uploaderBookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 bookmarkDataIsStale: &isStale) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    @MainActor
    static func chooseProgram() -> URL? {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose the program that uploads an image and prints its URL.")
        panel.prompt = String(localized: "Use Program")
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = try? url.bookmarkData(options: .withSecurityScope) else { return nil }
        UserDefaults.standard.set(bookmark, forKey: ImageSettings.uploaderBookmarkKey)
        return url
    }

    enum UploadError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            if case .failed(let output) = self {
                return String(localized: "The upload command did not print a URL. \(output)")
            }
            return nil
        }
    }

    /// Runs off the main thread; 60 s timeout.
    static func upload(_ file: URL, with configuration: Configuration) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = configuration.executable
            process.arguments = configuration.arguments.map { $0 == "{file}" ? file.path : $0 }
            if !configuration.arguments.contains("{file}") { process.arguments?.append(file.path) }
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let deadline = Date(timeIntervalSinceNow: 60)
            while process.isRunning, Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
            if process.isRunning { process.terminate() }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(bytes: data, encoding: .utf8) ?? ""
            let url = text.split(whereSeparator: \.isNewline).reversed()
                .first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
                .flatMap { URL(string: String($0).trimmingCharacters(in: .whitespaces)) }
            guard let url else { throw UploadError.failed(String(text.suffix(300))) }
            return url
        }.value
    }
}
