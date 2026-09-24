import AppKit
import XCTest

/// Smart paste, Insert commands and Copy As in the real editor.
final class ClipboardUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testPasteInsertAndCopyAs() throws {
        let fileName = "clip-\(UUID().uuidString.prefix(8)).md"
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-HashlineUITestDocument", fileName]
        app.launch()
        defer { app.terminate() }
        let textView = app.windows[fileName].textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        let pasteboard = NSPasteboard.general

        // HTML from a browser becomes Markdown.
        pasteboard.clearContents()
        pasteboard.setString("<p>Hello <b>world</b></p>", forType: .html)
        pasteboard.setString("Hello world", forType: .string)
        textView.typeKey("v", modifierFlags: .command)
        XCTAssertEqual(textView.value as? String, "Hello **world**")

        // A URL pasted over selected text makes a link.
        textView.typeText(" docs")
        textView.typeKey(.leftArrow, modifierFlags: [.shift, .option])
        pasteboard.clearContents()
        pasteboard.setString("https://example.com", forType: .string)
        textView.typeKey("v", modifierFlags: .command)
        XCTAssertEqual(textView.value as? String, "Hello **world** [docs](https://example.com)")

        // Footnote: reference at the caret, definition at the end, one undo step.
        app.menuBars.menuBarItems["Format"].click()
        app.menuBars.menuBarItems["Format"].menuItems["Footnote"].click()
        XCTAssertEqual(textView.value as? String, "Hello **world** [docs](https://example.com)[^1]\n\n[^1]: ")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(textView.value as? String, "Hello **world** [docs](https://example.com)")

        // Copy as plain text (whole document when nothing is selected).
        app.menuBars.menuBarItems["Edit"].click()
        app.menuBars.menuBarItems["Edit"].menuItems["Copy as Plain Text"].click()
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello world docs")
    }
}
