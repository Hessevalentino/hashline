import AppKit
import XCTest

/// Pasting an image copies it into assets/ next to the document and inserts a relative link.
final class ImageUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testPasteImageCreatesAssetAndLink() throws {
        let fileName = "img-\(UUID().uuidString.prefix(8)).md"
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-HashlineUITestDocument", fileName,
                               "-showsLibrary", "NO"]
        app.launch()
        defer { app.terminate() }
        let textView = app.windows[fileName].textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        app.typeKey("s", modifierFlags: .command)  // the document exists on disk (created by the hook)

        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)

        textView.typeKey("v", modifierFlags: .command)
        let value = try XCTUnwrap(textView.value as? String)
        XCTAssertTrue(value.hasPrefix("![image-"), value)
        XCTAssertTrue(value.contains("](assets/image-"), value)
        XCTAssertTrue(value.hasSuffix(".png)"), value)
    }
}
