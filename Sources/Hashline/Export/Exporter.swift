import AppKit
import HashlineCore
import UniformTypeIdentifiers

/// What a document can be exported to.
enum ExportFormat: Hashable, CaseIterable {
    case html, pdf, png
    case pandoc(PandocFormat)

    static var allCases: [ExportFormat] { [.html, .pdf, .png] + PandocFormat.allCases.map(ExportFormat.pandoc) }

    var title: String {
        switch self {
        case .html: "HTML"
        case .pdf: "PDF"
        case .png: String(localized: "PNG Image")
        case .pandoc(.docx): String(localized: "Word (DOCX)")
        case .pandoc(.odt): String(localized: "OpenDocument (ODT)")
        case .pandoc(.rtf): String(localized: "Rich Text (RTF)")
        case .pandoc(let format): format.title
        }
    }

    var fileExtension: String {
        switch self {
        case .html: "html"
        case .pdf: "pdf"
        case .png: "png"
        case .pandoc(let format): format.fileExtension
        }
    }

    var identifier: String {
        if case .pandoc(let format) = self { return "pandoc-" + format.rawValue }
        return fileExtension
    }

    init?(identifier: String) {
        guard let format = Self.allCases.first(where: { $0.identifier == identifier }) else { return nil }
        self = format
    }

    var contentType: UTType { UTType(filenameExtension: fileExtension) ?? .data }
}

/// File ▸ Export: HTML, PDF and PNG from the same renderer as the preview; other formats via Pandoc.
@MainActor
enum Exporter {
    private static let lastFormatKey = "lastExportFormat"

    /// Asks where to save (with a format menu when `format` is nil, ⇧⌘E) and exports.
    static func export(_ session: EditorSession, format: ExportFormat?) {
        guard let window = session.textView?.window else { return }
        let last = UserDefaults.standard.string(forKey: lastFormatKey).flatMap(ExportFormat.init(identifier:))
        var chosen = format ?? last ?? .pdf
        let baseName = session.documentURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = baseName + "." + chosen.fileExtension
        panel.allowedContentTypes = [chosen.contentType]
        if let folder = session.documentURL?.deletingLastPathComponent() { panel.directoryURL = folder }
        var accessory: FormatAccessory?
        if format == nil {
            let view = FormatAccessory(selected: chosen) { newFormat in
                chosen = newFormat
                panel.allowedContentTypes = [newFormat.contentType]
                let name = (panel.nameFieldStringValue as NSString).deletingPathExtension
                panel.nameFieldStringValue = name + "." + newFormat.fileExtension
            }
            panel.accessoryView = view.view
            accessory = view
        }
        panel.beginSheetModal(for: window) { response in
            _ = accessory
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                UserDefaults.standard.set(chosen.identifier, forKey: lastFormatKey)
                if case .pandoc = chosen, !PandocRunner.ensureConfigured(for: window) { return }
                Task { await run(session, format: chosen, to: url, window: window) }
            }
        }
    }

    static func run(_ session: EditorSession, format: ExportFormat, to url: URL, window: NSWindow) async {
        let signpost = Performance.signposter.beginInterval("Export")
        let started = ContinuousClock.now
        let progress = ProgressSheet(title: String(localized: "Exporting as \(format.title)…"), window: window)
        defer { progress.close() }
        do {
            let input = try Input(session)
            switch format {
            case .html: try await writeHTML(input, to: url)
            case .pdf: try await writePDF(input, to: url)
            case .png: try await writePNG(input, to: url)
            case .pandoc(let pandocFormat): try await writePandoc(input, format: pandocFormat, to: url)
            }
            let elapsed = (ContinuousClock.now - started).milliseconds
            Performance.logger.notice(
                "Export \(format.identifier, privacy: .public): \(elapsed, format: .fixed(precision: 0)) ms")
        } catch {
            Performance.logger.error("Export failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert(error: error)
            alert.messageText = String(localized: "The document could not be exported as \(format.title).")
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
        Performance.signposter.endInterval("Export", signpost)
    }

    /// A consistent copy of what is exported, taken on the main actor.
    @MainActor
    private struct Input {
        let text: NSString
        let blocks: [MarkdownBlock]
        let documentURL: URL?
        let title: String

        init(_ session: EditorSession) throws {
            guard let blocks = session.highlighter?.blockMap?.blocks else { throw CocoaError(.fileReadUnknown) }
            text = NSString(string: session.document.textStorage.string)
            self.blocks = blocks
            documentURL = session.documentURL
            title = ExportDocument.title(text: text, blocks: blocks,
                                         fallback: documentURL?.deletingPathExtension().lastPathComponent ?? "Untitled")
        }

        /// The page: `forScreen` resolves local images through the app (off-screen rendering);
        /// otherwise image paths stay as written.
        func page(forScreen: Bool, diagrams: [String: String] = [:]) -> String {
            var options = PreviewController.options(.export, documentURL: documentURL, text: text)
            options.resolveImages = forScreen
            options.diagrams = diagrams
            var body = ExportDocument.body(blocks: blocks, text: text, options: options)
            // Off-screen pages never scroll, so lazy images would never load.
            if forScreen { body = body.replacingOccurrences(of: " loading=\"lazy\"", with: "") }
            return ExportDocument.html(body: body, title: title, stylesheet: Exporter.stylesheet(for: body),
                                       language: Locale.current.language.languageCode?.identifier ?? "en")
        }

        var hasDiagrams: Bool { ExportDocument.containsDiagrams(blocks) }
        var outline: [OutlineItem] { DocumentOutline.items(in: blocks, text: text) }
    }

    // MARK: Formats

    private static func writeHTML(_ input: Input, to url: URL) async throws {
        var diagrams: [String: String] = [:]
        if input.hasDiagrams {
            let page = ExportPage()
            try await page.load(input.page(forScreen: true))
            diagrams = await page.renderDiagrams()
        }
        try Data(input.page(forScreen: false, diagrams: diagrams).utf8).write(to: url, options: .atomic)
    }

    private static func renderedPage(_ input: Input) async throws -> ExportPage {
        let page = ExportPage()
        try await page.load(input.page(forScreen: true))
        if input.hasDiagrams { _ = await page.renderDiagrams() }
        return page
    }

    private static func writePDF(_ input: Input, to url: URL) async throws {
        // The print system writes into a file of our own; the result is then moved to the chosen place.
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let page = try await renderedPage(input)
        try await page.writePDF(to: temporary, title: input.title, outline: input.outline)
        try replaceItem(at: url, with: temporary)
    }

    private static func writePNG(_ input: Input, to url: URL) async throws {
        let page = try await renderedPage(input)
        try await page.pngData().write(to: url, options: .atomic)
    }

    private static func writePandoc(_ input: Input, format: PandocFormat, to url: URL) async throws {
        let output = "export." + format.fileExtension
        let arguments = Pandoc.exportArguments(format: format, outputPath: output,
                                               resourcePath: input.documentURL?.deletingLastPathComponent())
        let data = try await PandocRunner.run(arguments: arguments, input: Data((input.text as String).utf8),
                                              resultFile: output)
        try data.write(to: url, options: .atomic)
    }

    private static func replaceItem(at url: URL, with source: URL) throws {
        let data = try Data(contentsOf: source)
        try data.write(to: url, options: .atomic)
    }

    // MARK: Styles

    static func stylesheet(for body: String) -> String {
        func css(_ name: String) -> String {
            Bundle.main.url(forResource: name, withExtension: "css")
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        }
        // Exports are for paper and other screens: always the chosen light theme.
        var sheet = ThemeStore.shared.theme(dark: false).css + """

            pre code.hljs { background: transparent; padding: 0; }
            .math-display { overflow-x: auto; margin: 1em 0; }
            .mermaid-diagram svg { max-width: 100%; height: auto; }
            .mermaid-diagram[data-rendered="true"] > pre { display: none; }
            .front-matter { display: none; }
            .footnote { font-size: 0.85em; opacity: 0.85; }
            .task-list-item { list-style: none; }
            .task-list-item > input[type=checkbox] { margin: 0 0.4em 0 -1.35em; vertical-align: middle; }
            @media print {
                body { max-width: none; }
                pre, blockquote, table, img, svg, .math-display { break-inside: avoid; }
                h1, h2, h3, h4, h5, h6 { break-after: avoid; }
                a { color: inherit; }
            }

            """
        if body.contains("class=\"katex") { sheet += css("katex-inline") }
        return sheet
    }

    // MARK: Import

    /// File ▸ Import: converts a Word, OpenDocument, RTF, ePub, HTML… file with Pandoc to Markdown,
    /// asks where to save it and opens it.
    static func importDocument() {
        guard PandocRunner.ensureConfigured(for: NSApp.keyWindow) else { return }
        let open = NSOpenPanel()
        open.prompt = String(localized: "Import")
        open.message = String(localized: "Choose a document to convert to Markdown.")
        open.allowedContentTypes = Pandoc.importExtensions.compactMap { UTType(filenameExtension: $0) }
        guard open.runModal() == .OK, let source = open.url,
              let data = try? Data(contentsOf: source),
              let arguments = Pandoc.importArguments(fileExtension: source.pathExtension, inputPath: "in") else {
            return
        }
        Task {
            do {
                let markdown = try await PandocRunner.run(arguments: arguments, input: data)
                let save = NSSavePanel()
                save.allowedContentTypes = [.markdown]
                save.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + ".md"
                if let library = LibraryStore.shared.folder { save.directoryURL = library }
                guard save.runModal() == .OK, let target = save.url else { return }
                try markdown.write(to: target, options: .atomic)
                LibraryStore.shared.openDocument(at: target, besides: NSApp.keyWindow)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}

/// The format menu under the save panel (⇧⌘E).
@MainActor
private final class FormatAccessory: NSObject {
    let view: NSView
    private let popUp: NSPopUpButton
    private let onChange: (ExportFormat) -> Void

    init(selected: ExportFormat, onChange: @escaping (ExportFormat) -> Void) {
        self.onChange = onChange
        popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        for format in ExportFormat.allCases {
            popUp.addItem(withTitle: format.title)
            popUp.lastItem?.representedObject = format.identifier
            if case .pandoc(.docx) = format { popUp.menu?.insertItem(.separator(), at: popUp.numberOfItems - 1) }
        }
        popUp.selectItem(withTitle: selected.title)
        let label = NSTextField(labelWithString: String(localized: "Format:"))
        let stack = NSStackView(views: [label, popUp])
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        view = stack
        super.init()
        popUp.target = self
        popUp.action = #selector(changed(_:))
    }

    @objc private func changed(_ sender: NSPopUpButton) {
        guard let identifier = sender.selectedItem?.representedObject as? String,
              let format = ExportFormat(identifier: identifier) else { return }
        onChange(format)
    }
}

/// “Exporting…” sheet, shown only when an export takes longer than a moment (long PDFs).
@MainActor
private final class ProgressSheet {
    private var sheet: NSWindow?
    private var task: Task<Void, Never>?

    init(title: String, window: NSWindow) {
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 80), styleMask: [.titled],
                                 backing: .buffered, defer: false)
            let indicator = NSProgressIndicator()
            indicator.style = .bar
            indicator.isIndeterminate = true
            indicator.startAnimation(nil)
            let stack = NSStackView(views: [NSTextField(labelWithString: title), indicator])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
            indicator.widthAnchor.constraint(equalToConstant: 280).isActive = true
            sheet.contentView = stack
            window.beginSheet(sheet, completionHandler: nil)
            self.sheet = sheet
        }
    }

    func close() {
        task?.cancel()
        if let sheet { sheet.sheetParent?.endSheet(sheet) }
        sheet = nil
    }
}
