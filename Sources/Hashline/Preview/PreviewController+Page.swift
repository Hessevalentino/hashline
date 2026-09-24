import AppKit
import HashlineCore
import SwiftUI
import WebKit

/// The preview page and the scripts the app runs in its isolated content world.
extension PreviewController {
    // MARK: Page

    /// The empty page with both chosen themes; the system appearance picks one. Without remote images
    /// the Content Security Policy blocks http(s) images, so nothing is fetched from the network.
    static func page(light: String, dark: String, remoteImages: Bool = true) -> String {
        let images = remoteImages ? "https: http: data: hashline-asset:" : "data: hashline-asset:"
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" \
        content="default-src 'none'; img-src \(images); \
        style-src 'unsafe-inline'; font-src data:">
        <style>
        /* Off-screen blocks skip layout and painting; large documents stay cheap. */
        body > [data-block] { content-visibility: auto; contain-intrinsic-size: auto 1.5em; }
        .math-display { overflow-x: auto; margin: 1em 0; }
        .mermaid-diagram svg { max-width: 100%; height: auto; }
        .mermaid-diagram[data-rendered="true"] > pre { display: none; }
        .mermaid-error { color: #d73a49; font-size: 0.85em; }
        .footnote { font-size: 0.85em; opacity: 0.85; }
        /* Reading mode: the preview alone, as a comfortable page (beats every theme). */
        html.hashline-reading body { max-width: 44em !important; margin: 0 auto !important;
            padding: 48px 32px 96px !important; font-size: 17px !important; line-height: 1.7 !important; }
        .task-list-item { list-style: none; }
        .task-list-item > input[type=checkbox] { margin: 0 0.4em 0 -1.35em; vertical-align: middle; }
        </style>
        <style id="hashline-theme-light" media="(prefers-color-scheme: light)">\(light)</style>
        <style id="hashline-theme-dark" media="(prefers-color-scheme: dark)">\(dark)</style>
        <style>pre code.hljs { background: transparent; padding: 0; }</style>
        </head><body></body></html>
        """
    }

    /// Replaces the theme styles in place: no reload, no re-render, scroll position kept.
    static let themeScript = """
        document.getElementById('hashline-theme-light').textContent = light;
        document.getElementById('hashline-theme-dark').textContent = dark;
        """

    /// Applies a PreviewUpdate: removes the replaced blocks and inserts the new run after `anchor`.
    static let patchScript = """
        const body = document.body;
        const byID = (id) => body.querySelector('[data-block="' + CSS.escape(id) + '"]');
        for (const id of removed) { const element = byID(id); if (element) { element.remove(); } }
        const template = document.createElement('template');
        template.innerHTML = html;
        const anchorElement = anchor === null ? null : byID(anchor);
        body.insertBefore(template.content, anchorElement ? anchorElement.nextSibling : body.firstChild);
        """

    func receive(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let block = body["block"] as? String,
              let task = body["task"] as? Int else { return }
        onTaskToggle?(block, task)
    }

    /// Task checkboxes toggle the source instead of their own state; the preview then re-renders.
    static let clickScript = """
        document.addEventListener('click', (event) => {
            const box = event.target.closest('input[type=checkbox][data-task]');
            if (!box) { return; }
            event.preventDefault();
            const block = box.closest('[data-block]');
            if (!block) { return; }
            window.webkit.messageHandlers.hashline.postMessage({
                block: block.dataset.block, task: Number(box.dataset.task)
            });
        }, true);
        """

    static let scrollScript = """
        const element = document.querySelector('[data-block="' + CSS.escape(id) + '"]');
        if (element) {
            const rect = element.getBoundingClientRect();
            window.scrollTo(0, window.scrollY + rect.top + fraction * rect.height);
        }
        """

}

// MARK: Math and diagrams

extension PreviewController {
    /// KaTeX styles (with fonts as data URLs) and Mermaid load only when a document needs them.
    func renderRichContent(in html: String) {
        if !hasKaTeXStyles, html.contains("class=\"katex") { injectKaTeXStyles() }
        if html.contains("mermaid-diagram") { renderMermaid() }
    }

    private func injectKaTeXStyles() {
        hasKaTeXStyles = true
        guard let url = Bundle.main.url(forResource: "katex-inline", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else { return }
        webView?.callAsyncJavaScript(
            "const style = document.createElement('style'); style.textContent = css; document.head.appendChild(style);",
            arguments: ["css": css], in: nil, in: .defaultClient, completionHandler: nil
        )
    }

    private func renderMermaid() {
        switch mermaidState {
        case .ready:
            webView?.callAsyncJavaScript(Self.mermaidRenderScript, arguments: [:], in: nil, in: .defaultClient,
                                         completionHandler: Self.logMermaidResult)
        case .loading:
            break  // renders once loaded
        case .notLoaded:
            mermaidState = .loading
            Task { @MainActor [weak self] in
                let source = await Task.detached(priority: .userInitiated) { Self.mermaidSource() }.value
                guard let self, let source, let webView = self.webView else { return }
                // Global scope of the app's isolated world; the page itself cannot run it.
                webView.evaluateJavaScript(source, in: nil, in: .defaultClient) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.mermaidState = .ready
                        self.webView?.callAsyncJavaScript(Self.mermaidSetupScript + Self.mermaidRenderScript,
                                                          arguments: [:], in: nil, in: .defaultClient,
                                                          completionHandler: Self.logMermaidResult)
                    }
                }
            }
        }
    }

    /// Totals since the page loaded: diagrams rendered by Mermaid and diagrams taken from the cache.
    private static func logMermaidResult(_ result: Result<Any, any Error>) {
        switch result {
        case .success(let value):
            let totals = value as? [String: Any]
            let rendered = totals?["rendered"] as? Int ?? 0
            let cached = totals?["cached"] as? Int ?? 0
            Performance.logger.notice("Mermaid diagrams: \(rendered) rendered, \(cached) from cache")
        case .failure(let error):
            Performance.logger.error("Mermaid failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Mermaid ships LZFSE-compressed (1.5 MB instead of 5.4 MB) and is unpacked on first use.
    nonisolated static func mermaidSource() -> String? {
        guard let url = Bundle.main.url(forResource: "mermaid.min.js", withExtension: "lzfse"),
              let data = try? Data(contentsOf: url),
              let unpacked = try? (data as NSData).decompressed(using: .lzfse) as Data else { return nil }
        return String(data: unpacked, encoding: .utf8)
    }

    static let mermaidSetupScript = """
        mermaid.initialize({
            startOnLoad: false,
            securityLevel: 'strict',
            theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default'
        });
        window.hashlineMermaid = { cache: new Map(), counter: 0, rendered: 0, cached: 0 };
        """

    /// Renders every diagram not rendered yet; identical sources come from the cache.
    static let mermaidRenderScript = """
        const state = window.hashlineMermaid;
        for (const element of document.querySelectorAll('.mermaid-diagram:not([data-rendered])')) {
            const code = element.dataset.mermaid;
            let svg = state.cache.get(code);
            if (svg) {
                state.cached += 1;
            } else {
                try {
                    state.counter += 1;
                    svg = (await mermaid.render('hashline-mermaid-' + state.counter, code)).svg;
                    state.cache.set(code, svg);
                    state.rendered += 1;
                } catch (error) {
                    element.dataset.rendered = 'error';
                    const message = document.createElement('p');
                    message.className = 'mermaid-error';
                    message.textContent = String(error && error.message ? error.message : error);
                    element.appendChild(message);
                    continue;
                }
            }
            const holder = document.createElement('div');
            holder.innerHTML = svg;
            element.prepend(holder);
            element.dataset.rendered = 'true';
        }
        return { rendered: state.rendered, cached: state.cached };
        """
}

/// Blocks handed to the background render. The Markdown tree is immutable and the array is a copy,
/// so reading it on another thread cannot race with editing.
struct UncheckedBlocks: @unchecked Sendable {
    let blocks: [MarkdownBlock]
    let head: NSString?
}

/// Breaks the retain cycle user content controller → handler → controller → web view.
final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: PreviewController?

    init(_ target: PreviewController) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { target?.receive(message) }
    }
}

/// Hosts the controller's container in SwiftUI.
struct PreviewPane: NSViewRepresentable {
    let controller: PreviewController

    func makeNSView(context: Context) -> NSView {
        controller.containerView
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
