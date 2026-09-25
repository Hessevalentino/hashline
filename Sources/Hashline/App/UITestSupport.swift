#if DEBUG || HASHLINE_TEST_HOOKS
import AppKit
import HashlineCore
import WebKit

/// Debug-only launch arguments for UI tests and visual checks.
/// - `-HashlineUITestDocument <name>` opens (creating if needed) a file in the app container,
///   because UI tests cannot drive the sandbox's out-of-process save panel.
/// - `-HashlineDebugSnapshot <name.png>` writes a PNG of the front window (editor + preview)
///   to the container's tmp folder after two seconds.
/// - `-HashlineTypingBenchmark <count>` types `count` characters into the editor through
///   `NSWindow.sendEvent` (no XCTest, no focus change, no dead keys), logs the latency and quits.
/// - `-HashlineModeBenchmark YES` switches each view mode on and off and logs the times
///   (`Mode switch …`). Do not pass the view-mode keys themselves as arguments: they would win.
/// - `-HashlineSplitDragTest <divider>` drags that divider (0 = library when shown) 120 points left with
///   mouse events sent to the window (NSSplitView's own tracking loop), then narrows the window by
///   300 points and logs the item widths and saved settings (`Split drag …`).
@MainActor
final class UITestSupport: NSObject {
    func applicationDidFinishLaunching() {
        let defaults = UserDefaults.standard
        if let name = defaults.string(forKey: "HashlineUITestDocument") {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: Data())
            }
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
        let benchmarkCount = defaults.integer(forKey: "HashlineTypingBenchmark")
        if benchmarkCount > 0 {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                await Self.runTypingBenchmark(count: benchmarkCount)
            }
        }
        startServiceHook(defaults)
        if let folder = defaults.string(forKey: "HashlineExportTest") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                await Self.runExportTest(into: folder)
            }
        }
        startShowcaseHook(defaults)
        if defaults.bool(forKey: "HashlineModeBenchmark") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                await Self.runModeBenchmark()
            }
        }
        if defaults.object(forKey: "HashlineSplitDragTest") != nil {
            let divider = defaults.integer(forKey: "HashlineSplitDragTest")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                await Self.runSplitDragTest(divider: divider)
            }
        }
        if let snapshotName = defaults.string(forKey: "HashlineDebugSnapshot") {
            let delay = max(defaults.double(forKey: "HashlineDebugSnapshotDelay"), 2)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                await Self.writeSnapshot(named: snapshotName)
            }
        }
    }

    /// Queues the drag and the mouse-up, then sends the mouse-down: NSSplitView tracks the rest itself.
    private static func runSplitDragTest(divider: Int) async {
        guard let window = NSApp.orderedWindows.first(where: { DocumentReveal.session(for: $0) != nil }),
              let session = DocumentReveal.session(for: window) else {
            return Performance.logger.error("Split drag: no document window")
        }
        var item: NSView? = session.editorScrollView
        while let current = item, !(current.superview is NSSplitView) { item = current.superview }
        guard let split = item?.superview as? NSSplitView, divider < split.arrangedSubviews.count - 1 else {
            return Performance.logger.error("Split drag: no split view or divider")
        }
        func log(_ step: String) {
            let widths = split.arrangedSubviews.map { String(Int($0.frame.width)) }.joined(separator: " | ")
            let defaults = UserDefaults.standard
            let ratio = defaults.double(forKey: SplitSettings.editorFractionKey)
            let library = defaults.double(forKey: SplitSettings.libraryWidthKey)
            Performance.logger.notice(
                "Split drag \(step, privacy: .public): \(widths, privacy: .public), ratio \(ratio), library \(library)")
        }
        log("before")
        let dividerX = split.arrangedSubviews[divider].frame.maxX + split.dividerThickness / 2
        let start = split.convert(NSPoint(x: dividerX, y: split.bounds.midY), to: nil)
        func event(_ type: NSEvent.EventType, _ offset: CGFloat) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: start.x + offset, y: start.y), modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
        }
        for step in 1...6 { event(.leftMouseDragged, CGFloat(-20 * step)).map { NSApp.postEvent($0, atStart: false) } }
        event(.leftMouseUp, -120).map { NSApp.postEvent($0, atStart: false) }
        event(.leftMouseDown, 0).map(window.sendEvent)
        try? await Task.sleep(for: .milliseconds(300))
        log("dragged")
        var frame = window.frame
        frame.size.width -= 300
        window.setFrame(frame, display: true)
        try? await Task.sleep(for: .milliseconds(300))
        log("narrowed")
    }

    private func startServiceHook(_ defaults: UserDefaults) {
        if let text = defaults.string(forKey: "HashlineServiceTest") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("HashlineServiceTest"))
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                let performed = NSPerformService("New Hashline Document Containing Selection", pasteboard)
                Performance.logger.notice("Service test: performed \(performed)")
            }
        }
        if let corpus = defaults.string(forKey: "HashlineXSSTest") {
            Task { @MainActor in await XSSProbe.run(corpusNamed: corpus) }
        }
    }

    private func startShowcaseHook(_ defaults: UserDefaults) {
        if defaults.bool(forKey: "HashlineShowcase") {
            // Screenshots for the README: the window floats visible (WebKit does not paint covered
            // windows) without activating the app, so it never takes the keyboard focus.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                for window in NSApp.windows where window.isVisible && window.contentView != nil {
                    window.level = .floating
                    window.orderFrontRegardless()
                }
            }
        }
    }

    @MainActor
    private static func writeSnapshot(named name: String) async {
        // The frame view includes the title bar and toolbar.
        guard let window = NSApp.orderedWindows.first(where: { $0.isVisible && $0.contentView != nil }),
              let content = window.contentView?.superview ?? window.contentView,
              let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let image = NSImage(size: content.bounds.size)
        image.addRepresentation(bitmap)

        // Web content renders out of process and is missing from cacheDisplay; draw its own snapshot on top.
        if let webView = findWebView(in: content),
           let webImage = try? await webView.takeSnapshot(configuration: nil) {
            let frame = webView.convert(webView.bounds, to: content)
            image.lockFocusFlipped(content.isFlipped)
            webImage.draw(in: frame)
            image.unlockFocus()
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent(name))
    }

    /// Exports the front document to every format into the container's tmp/`folder`, then quits.
    @MainActor
    private static func runExportTest(into folder: String) async {
        guard let window = NSApp.orderedWindows.first(where: { $0.firstResponder is EditorTextView }),
              let session = DocumentReveal.session(for: window) else {
            Performance.logger.error("Export test: no editor window")
            return
        }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for format in ExportFormat.allCases {
            if case .pandoc = format, PandocRunner.executable == nil { continue }
            let file = target.appendingPathComponent("export." + format.fileExtension)
            await Exporter.run(session, format: format, to: file, window: window)
        }
        NSApp.terminate(nil)
    }

    @MainActor
    private static func runModeBenchmark() async {
        let defaults = UserDefaults.standard
        let switches: [(name: String, key: String)] = [
            ("reading", ViewSettings.readingModeKey), ("focus", ViewSettings.focusModeKey),
            ("typewriter", ViewSettings.typewriterModeKey), ("status bar", ViewSettings.statusBarKey),
            ("text width", ViewSettings.textWidthKey), ("theme", AppearanceSettings.darkThemeKey),
            ("font", AppearanceSettings.fontSizeKey),
        ]
        for mode in switches {
            let values: [Any] = switch mode.key {
            case ViewSettings.textWidthKey: [0, ViewSettings.defaultWidth]
            case AppearanceSettings.darkThemeKey: ["Solarized Dark", AppearanceSettings.defaultDark]
            case AppearanceSettings.fontSizeKey: [16.0, AppearanceSettings.defaultFontSize]
            default: [true, false]
            }
            for value in values {
                ModeSwitchMetrics.measure(mode.name) { defaults.set(value, forKey: mode.key) }
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
        NSApp.terminate(nil)
    }

    /// Types characters at a steady pace (like a fast typist, 50 ms apart); `TypingLatency`
    /// logs p50/p95/max per 100 keystrokes.
    @MainActor
    private static func runTypingBenchmark(count: Int) async {
        guard let window = NSApp.orderedWindows.first(where: { $0.firstResponder is EditorTextView }) else {
            Performance.logger.error("Typing benchmark: no editor window")
            return
        }
        let characters = Array("Příliš žluťoučký kůň úpěl ďábelské ódy. ")
        for index in 0..<count {
            let character = String(characters[index % characters.count])
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                                                timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window.windowNumber, context: nil,
                                                characters: character, charactersIgnoringModifiers: character,
                                                isARepeat: false, keyCode: 0) {
                    window.sendEvent(event)
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        // `-HashlineTypingBenchmarkKeepOpen YES` leaves the edited document open (conflict checks).
        guard !UserDefaults.standard.bool(forKey: "HashlineTypingBenchmarkKeepOpen") else { return }
        try? await Task.sleep(for: .milliseconds(500))
        NSApp.terminate(nil)
    }

    @MainActor
    private static func findWebView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        for subview in view.subviews {
            if let found = findWebView(in: subview) { return found }
        }
        return nil
    }
}

/// F10: renders the XSS corpus as an exported page and as the preview page, loads each into a web
/// view with page JavaScript ON (the worst case: an export opened in a browser) and checks that no
/// vector ran. Logs `XSS probe …: title …, handlers …` and quits.
@MainActor
enum XSSProbe {
    private final class Loader: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Never>?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            continuation?.resume()
            continuation = nil
        }
    }

    static func run(corpusNamed name: String) async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            Performance.logger.error("XSS probe: corpus missing")
            return
        }
        let text = markdown as NSString
        let blocks = BlockMap(text: markdown).blocks
        var options = PreviewController.options(.export, documentURL: nil, text: text)
        options.extensions.highlight = true
        options.extensions.superscript = true
        options.extensions.subscriptText = true
        let exportBody = ExportDocument.body(blocks: blocks, text: text, options: options)
        let exportPage = ExportDocument.html(body: exportBody, title: "corpus", stylesheet: "")
        let previewBody = PreviewRenderer.renderAll(blocks, text: text,
                                                    options: PreviewController.options(.preview, documentURL: nil,
                                                                                       text: text))
            .map(\.html).joined()
        let previewPage = PreviewController.page(light: "", dark: "")
            .replacingOccurrences(of: "<body></body>", with: "<body>\(previewBody)</body>")
        for (label, page, csp) in [("export", exportPage, true), ("preview", previewPage, true),
                                   ("export without CSP", exportPage.replacingOccurrences(
                                       of: "http-equiv=\"Content-Security-Policy\"", with: "name=\"x-removed\""),
                                    false)] {
            let result = await probe(page)
            Performance.logger.notice(
                "XSS probe \(label, privacy: .public) (CSP \(csp)): \(result, privacy: .public)")
        }
        // Control: unsanitized, the same kind of vector must run, or the probe proves nothing.
        let control = await probe("<html><head><title>corpus</title></head><body>"
                                  + "<img src=x onerror=\"document.title='PWNED'\"></body></html>")
        Performance.logger.notice("XSS probe control (unsanitized): \(control, privacy: .public)")
        NSApp.terminate(nil)
    }

    /// Loads `html` with JavaScript enabled, waits for late handlers (onerror, timers) and reports
    /// the title and any dangerous DOM that survived.
    private static func probe(_ html: String) async -> String {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let loader = Loader()
        webView.navigationDelegate = loader
        await withCheckedContinuation { continuation in
            loader.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
        try? await Task.sleep(for: .seconds(2))
        let script = """
            const all = [...document.querySelectorAll('*')];
            const handlers = all.filter(e => [...e.attributes].some(a => a.name.startsWith('on'))).length;
            const scripts = document.querySelectorAll('script, iframe, object, embed').length;
            const js = [...document.querySelectorAll('[href], [src]')]
                .filter(e => /^\\s*(javascript|vbscript|data:text)/i
                    .test(e.getAttribute('href') || e.getAttribute('src') || '')).length;
            return 'title ' + document.title + ', handlers ' + handlers
                + ', script elements ' + scripts + ', js urls ' + js;
            """
        let value = try? await webView.callAsyncJavaScript(script, arguments: [:], in: nil,
                                                           contentWorld: .defaultClient)
        return value as? String ?? "no result"
    }
}
#endif
