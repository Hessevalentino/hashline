import AppKit
import Observation
import HashlineCore
import SwiftUI
import WebKit

/// HTML preview in a WKWebView. The page runs no scripts of its own
/// (`allowsContentJavaScript = false`); the app patches the DOM through an isolated content world.
/// State shown around the preview.
@MainActor
@Observable
final class PreviewStatus {
    /// Folder with images the app may not read yet; the preview offers to grant access.
    var blockedFolder: URL?
}

@MainActor
final class PreviewController: NSObject, WKNavigationDelegate {
    /// Hosts the web view. Exists immediately; the web view is added by `load()` once the editor
    /// is editable, so creating WebKit never delays opening a document.
    let containerView = NSView()
    private(set) var webView: WKWebView?
    private let renderer = PreviewRenderer()
    var isLoaded = false
    var pendingBlocks: [MarkdownBlock]?
    /// Blocks the preview should show.
    var latestBlocks: [MarkdownBlock] = []
    /// Blocks rendered synchronously on the first patch; the rest renders in the background.
    private var streamLimit = Int.max
    private var isStreaming = false
    private var isPatching = false
    nonisolated(unsafe) private var defaultsObserver: NSObjectProtocol?
    nonisolated(unsafe) private var themeObserver: NSObjectProtocol?
    var appliedThemes = ""
    var appliedRemoteImages = true
    var isReading = false
    /// Blocks changed while a patch was in flight; patch again when it lands.
    private var isDirty = false
    /// Document text for document-level content (front matter); read on the main thread only.
    private var latestText: NSString?
    private static let firstBatch = 300
    /// Set by the session on every edit (kept for callers; the background render does not need it).
    var lastEdit = ContinuousClock.now - .seconds(1)
    private var hasReportedFirstRender = false
    private var pendingScroll: (id: String, fraction: Double)?
    /// A task checkbox was clicked: block id and task index within the block.
    var onTaskToggle: ((String, Int) -> Void)?
    /// Observable state shown around the preview (e.g. a folder whose images are blocked).
    let status = PreviewStatus()
    private let assetHandler = AssetSchemeHandler()
    /// The document's file; relative images resolve against its folder.
    var documentURL: URL? {
        didSet { if documentURL != oldValue { refresh() } }
    }
    private var isScrollScheduled = false

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
    }

    func load() {
        guard webView == nil else { return }
        let signpost = Performance.signposter.beginInterval("PreviewLoad")
        defer { Performance.signposter.endInterval("PreviewLoad", signpost) }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        // Messages only from the app's isolated world (the click listener below), never from the page.
        configuration.userContentController.add(MessageProxy(self), contentWorld: .defaultClient, name: "hashline")
        configuration.setURLSchemeHandler(assetHandler, forURLScheme: ImageLinks.assetScheme)
        assetHandler.onBlockedFolder = { [weak self] folder in
            if self?.status.blockedFolder == nil { self?.status.blockedFolder = folder }
        }
        let webView = WKWebView(frame: containerView.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.setAccessibilityLabel("Preview")
        // Syntax extensions are switched in the Format menu; re-render when they change.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // AppKit writes defaults often (window frames, toolbar); react only to our settings.
                guard let self else { return }
                if ImageSettings.loadsRemoteImages != self.appliedRemoteImages {
                    self.reloadPage()
                } else if self.options.extensions != self.appliedExtensions {
                    self.refresh()
                }
            }
        }
        themeObserver = NotificationCenter.default.addObserver(
            forName: .hashlineThemeChanged, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.updateThemeStyles() } }
        containerView.addSubview(webView)
        self.webView = webView
        webView.loadHTMLString(themedPage(), baseURL: nil)
    }

    func update(blocks: [MarkdownBlock], text: NSString? = nil) {
        if let text { latestText = text }
        guard isLoaded else {
            pendingBlocks = blocks
            return
        }
        latestBlocks = blocks
        if isPatching || isStreaming { isDirty = true } else { patch() }
    }

    private var appliedExtensions = InlineExtensionSettings()
    var hasKaTeXStyles = false
    var mermaidState = MermaidState.notLoaded

    enum MermaidState {
        case notLoaded, loading, ready
    }

    /// Optional syntax extensions (Format ▸ Syntax Extensions), off by default.
    private var options: HTMLRenderer.Options {
        Self.options(.preview, documentURL: documentURL, text: latestText)
    }

    /// Rendering options with the user's syntax extensions; shared by the preview and exports.
    static func options(_ base: HTMLRenderer.Options, documentURL: URL?, text: NSString?) -> HTMLRenderer.Options {
        var options = base
        options.frontMatterLabel = String(localized: "Front matter")
        let defaults = UserDefaults.standard
        options.extensions = InlineExtensionSettings(
            highlight: defaults.bool(forKey: SyntaxExtensionSettings.highlightKey),
            superscript: defaults.bool(forKey: SyntaxExtensionSettings.superscriptKey),
            subscriptText: defaults.bool(forKey: SyntaxExtensionSettings.subscriptKey),
            math: true
        )
        options.imageBase = ImageLinks.base(documentURL: documentURL, text: text)
        return options
    }

    /// After the user granted a folder: reload so blocked images load.
    func reloadAfterAccessGranted() {
        status.blockedFolder = nil
        reloadPage()
    }

    /// Re-renders everything, e.g. after an extension was switched on or off.
    func refresh() {
        guard isLoaded else { return }
        if isPatching || isStreaming { isDirty = true } else { patch() }
    }

    /// Sends one patch. The first patch of a large document shows the first screen at once and
    /// renders the rest off the main thread (`renderRestInBackground`).
    private func patch() {
        let options = self.options
        appliedExtensions = options.extensions
        let isInitial = streamLimit != Int.max
        let visibleCount = min(latestBlocks.count, streamLimit)
        let signpost = Performance.signposter.beginInterval("PreviewUpdate")
        let update = renderer.update(for: Array(latestBlocks.prefix(visibleCount)), text: latestText, options: options)
        Performance.signposter.endInterval("PreviewUpdate", signpost)
        if isInitial {
            streamLimit = Int.max
            if visibleCount < latestBlocks.count { renderRestInBackground(options: options) }
        }
        guard !update.isEmpty else { return }
        send(update)
    }

    private func send(_ update: PreviewUpdate) {
        isPatching = true
        let arguments: [String: Any] = ["anchor": update.anchor ?? NSNull(), "removed": update.removed,
                                        "html": update.html]
        webView?.callAsyncJavaScript(Self.patchScript, arguments: arguments,
                                     in: nil, in: .defaultClient) { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result {
                Performance.logger.error("Preview patch failed: \(error.localizedDescription, privacy: .public)")
            }
            self.reportFirstRender()
            self.renderRichContent(in: update.html)
            self.isPatching = false
            if self.isDirty {
                self.isDirty = false
                self.patch()
            }
        }
    }

    /// Renders the whole document on a background thread, then appends everything after the first
    /// screen in chunks. Edits made meanwhile are patched by the next regular update.
    private func renderRestInBackground(options: HTMLRenderer.Options) {
        isStreaming = true
        // Front matter detection only needs the start of the document; an immutable copy goes along.
        let input = UncheckedBlocks(
            blocks: latestBlocks,
            head: latestText.map { NSString(string: $0.substring(to: min($0.length, 20_000))) }
        )
        let firstCount = min(Self.firstBatch, latestBlocks.count)
        let extensions = options.extensions
        Task { @MainActor [weak self] in
            let entries = await Task.detached(priority: .utility) {
                PreviewRenderer.renderAll(input.blocks, text: input.head, options: options)
            }.value
            guard let self else { return }
            self.appendInChunks(entries, after: firstCount, extensions: extensions)
        }
    }

    private func appendInChunks(_ entries: [PreviewRenderer.RenderedEntry], after firstCount: Int,
                                extensions: InlineExtensionSettings) {
        renderer.markShown(entries.map(\.id), extensions: extensions)
        let rest = Array(entries.dropFirst(firstCount))
        let chunkSize = 2_000
        var anchor = entries.prefix(firstCount).last?.id
        var chunks: [(anchor: String?, html: String)] = []
        for start in stride(from: 0, to: rest.count, by: chunkSize) {
            let chunk = rest[start..<min(start + chunkSize, rest.count)]
            chunks.append((anchor, chunk.map(\.html).joined()))
            anchor = chunk.last?.id
        }
        sendChunks(chunks[...])
    }

    private func sendChunks(_ chunks: ArraySlice<(anchor: String?, html: String)>) {
        guard let chunk = chunks.first else {
            isStreaming = false
            // Catch up with edits made while rendering in the background.
            patch()
            return
        }
        let arguments: [String: Any] = ["anchor": chunk.anchor ?? NSNull(), "removed": [String](), "html": chunk.html]
        webView?.callAsyncJavaScript(Self.patchScript, arguments: arguments, in: nil,
                                     in: .defaultClient) { [weak self] _ in
            self?.renderRichContent(in: chunk.html)
            self?.sendChunks(chunks.dropFirst())
        }
    }

    /// Scrolls so the given block (at `fraction` of its height) is at the top. Coalesced per run loop turn.
    func scroll(toBlock id: String, fraction: Double) {
        pendingScroll = (id, fraction)
        guard !isScrollScheduled else { return }
        isScrollScheduled = true
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isScrollScheduled = false
                guard self.isLoaded, let target = self.pendingScroll else { return }
                self.webView?.callAsyncJavaScript(Self.scrollScript,
                                                 arguments: ["id": target.id, "fraction": target.fraction],
                                                 in: nil, in: .defaultClient, completionHandler: nil)
            }
        }
    }

    func scrollToBottom() {
        guard isLoaded else { return }
        webView?.callAsyncJavaScript("window.scrollTo(0, document.body.scrollHeight)", arguments: [:],
                                    in: nil, in: .defaultClient, completionHandler: nil)
    }

    private func reportFirstRender() {
        guard !hasReportedFirstRender else { return }
        hasReportedFirstRender = true
        if let elapsed = Performance.millisecondsSinceProcessStart() {
            Performance.logger.notice(
                "Preview rendered: \(elapsed, format: .fixed(precision: 1)) ms after process start"
            )
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.callAsyncJavaScript(Self.clickScript, arguments: [:], in: nil, in: .defaultClient,
                                    completionHandler: nil)
        isLoaded = true
        applyReadingClass()
        hasKaTeXStyles = false
        mermaidState = .notLoaded
        renderer.reset()
        streamLimit = Self.firstBatch
        if let blocks = pendingBlocks {
            pendingBlocks = nil
            update(blocks: blocks)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // Only the initial page may load; links open in the default browser.
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
                NSWorkspace.shared.open(url)
            } else if url.scheme == "about", let fragment = url.fragment(percentEncoded: false) {
                // In-page anchors: table of contents, footnotes.
                webView.callAsyncJavaScript(
                    "const target = document.getElementById(id); if (target) { target.scrollIntoView(); }",
                    arguments: ["id": fragment], in: nil, in: .defaultClient, completionHandler: nil
                )
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
    }

}
