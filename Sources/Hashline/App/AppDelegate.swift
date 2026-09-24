import AppKit
import HashlineCore

/// Registers the Services provider; in test builds also runs the launch-argument hooks.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = ServicesProvider()
    #if DEBUG || HASHLINE_TEST_HOOKS
    private let testSupport = UITestSupport()
    #endif

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppearanceMode.apply()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = services
        Updater.shared.start()
        #if DEBUG || HASHLINE_TEST_HOOKS
        testSupport.applicationDidFinishLaunching()
        #endif
    }
}

/// Services menu: “New Hashline Document Containing Selection” in any app. Rich text and HTML
/// selections arrive as Markdown.
final class ServicesProvider: NSObject {
    @objc func newDocumentFromSelection(_ pasteboard: NSPasteboard, userData: String?,
                                        error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let markdown: String?
        if let html = pasteboard.string(forType: .html), let converted = HTMLToMarkdown.convert(html) {
            markdown = converted
        } else {
            markdown = pasteboard.string(forType: .string)
        }
        guard let markdown, !markdown.isEmpty else {
            error.pointee = String(localized: "There is no text to put in a new document.") as NSString
            return
        }
        MainActor.assumeIsolated {
            DocumentReveal.openUntitled(containing: markdown)
        }
    }
}
