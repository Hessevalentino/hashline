import AppKit
import HashlineCore
import PDFKit
import WebKit

/// An off-screen web view that lays out an exported page: Mermaid diagrams render in the app's
/// isolated script world (the page itself runs no JavaScript), then it prints to PDF or snapshots
/// to PNG. Always light: exports are for paper and other people's screens.
@MainActor
final class ExportPage: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private let window: NSWindow
    private let assetHandler = AssetSchemeHandler()
    private var loadContinuation: CheckedContinuation<Void, Error>?

    init(width: CGFloat = 820) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(assetHandler, forURLScheme: ImageLinks.assetScheme)
        let frame = NSRect(x: 0, y: 0, width: width, height: 1_100)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.appearance = NSAppearance(named: .aqua)
        // Printing and snapshots need the view in a window; this one is never shown.
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ html: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?,
                 withError error: any Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    /// Renders the page's Mermaid diagrams and returns them as source → SVG.
    func renderDiagrams() async -> [String: String] {
        guard let source = await Task.detached(priority: .userInitiated, operation: {
            PreviewController.mermaidSource()
        }).value else { return [:] }
        do {
            _ = try await webView.evaluateJavaScript(source, in: nil, contentWorld: .defaultClient)
            _ = try await webView.callAsyncJavaScript(
                PreviewController.mermaidSetupScript + PreviewController.mermaidRenderScript,
                arguments: [:], in: nil, contentWorld: .defaultClient)
            let pairs = try await webView.callAsyncJavaScript("""
                return [...document.querySelectorAll('.mermaid-diagram')].map((element) => {
                    const svg = element.querySelector('svg');
                    return [element.dataset.mermaid, svg ? svg.outerHTML : ''];
                });
                """, arguments: [:], in: nil, contentWorld: .defaultClient) as? [[String]] ?? []
            var diagrams: [String: String] = [:]
            for pair in pairs where pair.count == 2 && !pair[1].isEmpty { diagrams[pair[0]] = pair[1] }
            return diagrams
        } catch {
            Performance.logger.error("Export diagrams failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    private func contentHeight() async -> CGFloat {
        let value = try? await webView.callAsyncJavaScript(
            "return document.documentElement.scrollHeight;", arguments: [:], in: nil, contentWorld: .defaultClient)
        return CGFloat((value as? NSNumber)?.doubleValue ?? 1_100)
    }

    // MARK: PDF

    /// Paginated PDF through the print system (A4 or Letter by locale), then bookmarks from the
    /// headings with PDFKit.
    func writePDF(to url: URL, title: String, outline: [OutlineItem]) async throws {
        let info = NSPrintInfo(dictionary: [.jobSavingURL: url])
        info.jobDisposition = .save
        info.paperSize = NSPrintInfo.shared.paperSize
        for edge in [\NSPrintInfo.topMargin, \.bottomMargin] { info[keyPath: edge] = 42 }
        for edge in [\NSPrintInfo.leftMargin, \.rightMargin] { info[keyPath: edge] = 36 }
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = webView.bounds
        let succeeded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let delegate = PrintCompletion { continuation.resume(returning: $0) }
            operation.runModal(for: window, delegate: delegate,
                               didRun: #selector(PrintCompletion.printOperationDidRun(_:success:contextInfo:)),
                               contextInfo: nil)
            objc_setAssociatedObject(operation, &PrintCompletion.key, delegate, .OBJC_ASSOCIATION_RETAIN)
        }
        guard succeeded else { throw CocoaError(.fileWriteUnknown) }
        let printed = ContinuousClock.now
        Self.addOutline(to: url, title: title, outline: outline)
        let elapsed = (ContinuousClock.now - printed).milliseconds
        Performance.logger.notice("PDF bookmarks: \(outline.count) in \(elapsed, format: .fixed(precision: 0)) ms")
    }

    /// Bookmarks: each heading is found as text in page order, nested by level.
    private static func addOutline(to url: URL, title: String, outline: [OutlineItem]) {
        guard let document = PDFDocument(url: url) else { return }
        document.documentAttributes = [PDFDocumentAttribute.titleAttribute: title,
                                       PDFDocumentAttribute.creatorAttribute: "Hashline"]
        if !outline.isEmpty, let firstPage = document.page(at: 0) {
            let root = PDFOutline()
            let parents = ExportDocument.outlineParents(levels: outline.map(\.level))
            var nodes: [PDFOutline] = []
            var finder = HeadingFinder(document: document)
            var destination = PDFDestination(page: firstPage,
                                             at: NSPoint(x: 0, y: firstPage.bounds(for: .mediaBox).maxY))
            for (index, item) in outline.enumerated() {
                if let found = finder.next(item.title) {
                    destination = found
                }
                let node = PDFOutline()
                node.label = item.title
                node.destination = destination
                let parent = parents[index].map { nodes[$0] } ?? root
                parent.insertChild(node, at: parent.numberOfChildren)
                nodes.append(node)
            }
            document.outlineRoot = root
            let slugs = outline.map { TableOfContents.slug($0.title) }
            let targets = Dictionary(zip(slugs, nodes.compactMap(\.destination)),
                                     uniquingKeysWith: { first, _ in first })
            fixSectionLinks(in: document, targets: targets)
        }
        document.write(to: url)
    }

    /// WebKit turns links to headings with non-ASCII ids (`#poznámky`) into `about:blank#…` URLs;
    /// point them at the heading's bookmark instead.
    private static func fixSectionLinks(in document: PDFDocument, targets: [String: PDFDestination]) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where annotation.type == "Link" {
                // The `#` arrives percent-encoded: `about:blank%23pozn%C3%A1mky`.
                guard let url = (annotation.action as? PDFActionURL)?.url ?? annotation.url, url.scheme == "about",
                      let decoded = url.absoluteString.removingPercentEncoding,
                      let fragment = decoded.split(separator: "#", maxSplits: 1).dropFirst().first,
                      let destination = targets[String(fragment)] else { continue }
                annotation.url = nil
                annotation.action = PDFActionGoTo(destination: destination)
            }
        }
    }

    // MARK: PNG

    /// The whole page as one image at 2× (capped at 16 000 pixels of height).
    func pngData() async throws -> Data {
        let width = webView.bounds.width
        let height = min(await contentHeight(), 8_000)
        window.setContentSize(NSSize(width: width, height: height))
        webView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
        // In points: on a Retina screen the image has twice as many pixels.
        configuration.snapshotWidth = NSNumber(value: Double(width))
        let image = try await webView.takeSnapshot(configuration: configuration)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return png
    }
}

/// Finds headings in a printed PDF in one pass over the page texts: each heading is the next line
/// that consists of exactly its title and is not a link (`[toc]` entries repeat every title).
private struct HeadingFinder {
    private let document: PDFDocument
    private let pages: [NSString]
    private var links: [Int: [CGRect]] = [:]
    private var page = 0
    private var offset = 0

    init(document: PDFDocument) {
        self.document = document
        pages = (0..<document.pageCount).map { (document.page(at: $0)?.string ?? "") as NSString }
    }

    mutating func next(_ title: String) -> PDFDestination? {
        let startPage = page, startOffset = offset
        for index in startPage..<pages.count {
            let text = pages[index]
            var location = index == startPage ? startOffset : 0
            while location < text.length {
                let found = text.range(of: title, range: NSRange(location: location, length: text.length - location))
                guard found.location != NSNotFound else { break }
                location = NSMaxRange(found)
                guard isWholeLine(found, in: text), let pdfPage = document.page(at: index) else { continue }
                // One character's box is enough for the position and far cheaper than a selection.
                let bounds = pdfPage.characterBounds(at: found.location)
                guard !linkRects(on: index).contains(where: { $0.intersects(bounds) }) else { continue }
                page = index
                offset = NSMaxRange(found)
                return PDFDestination(page: pdfPage, at: NSPoint(x: 0, y: bounds.maxY + 12))
            }
        }
        return nil
    }

    private func isWholeLine(_ range: NSRange, in text: NSString) -> Bool {
        let newlines = CharacterSet.newlines
        func isBreak(_ index: Int) -> Bool {
            guard index >= 0, index < text.length, let scalar = UnicodeScalar(text.character(at: index)) else {
                return true
            }
            return newlines.contains(scalar)
        }
        return isBreak(range.location - 1) && isBreak(NSMaxRange(range))
    }

    private mutating func linkRects(on index: Int) -> [CGRect] {
        if let cached = links[index] { return cached }
        let rects = document.page(at: index)?.annotations.filter { $0.type == "Link" }.map(\.bounds) ?? []
        links[index] = rects
        return rects
    }
}

/// Receives the print operation's Objective-C completion callback.
private final class PrintCompletion: NSObject {
    nonisolated(unsafe) static var key = 0
    private let completion: (Bool) -> Void

    init(_ completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    @objc func printOperationDidRun(_ operation: NSPrintOperation, success: Bool,
                                    contextInfo: UnsafeMutableRawPointer?) {
        completion(success)
    }
}
