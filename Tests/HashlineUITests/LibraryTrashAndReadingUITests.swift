import XCTest

/// 0.1.2: documents can be moved to the Trash from the library; the toolbar's book button shows the
/// rendered document alone.
final class LibraryTrashAndReadingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testMoveToTrashFromLibrary() throws {
        let library = "trash-\(UUID().uuidString.prefix(8))"
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-HashlineLibraryFolder", library, "-showsLibrary", "YES",
                               "-sidebarTab", "documents", "-HashlineUITestDocument", "\(library)/keep.md"]
        app.launch()
        defer { app.terminate() }
        let first = app.windows["keep.md"]
        XCTAssertTrue(first.textViews.firstMatch.waitForExistence(timeout: 5))
        first.textViews.firstMatch.typeText("# Keep")
        app.typeKey("s", modifierFlags: .command)

        // A second document to delete, created in the library (⌥⌘N) and saved with a title.
        app.typeKey("n", modifierFlags: [.command, .option])
        let second = app.windows["Untitled.md"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.textViews.firstMatch.typeText("# Throwaway")
        app.typeKey("s", modifierFlags: .command)

        let row = second.outlines.firstMatch.staticTexts["Throwaway"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The new document is listed")
        row.rightClick()
        second.menuItems["Move to Trash"].click()

        let gone = NSPredicate(format: "exists == false")
        let keep = app.windows["keep.md"]
        expectation(for: gone, evaluatedWith: keep.outlines.firstMatch.staticTexts["Throwaway"].firstMatch)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.windows["Untitled.md"].exists, "Its window closed")
        XCTAssertTrue(keep.outlines.firstMatch.staticTexts["Keep"].firstMatch.exists, "The other document stays")
    }

    @MainActor
    func testToolbarReadingModeShowsOnlyThePreview() throws {
        let fileName = "reading-\(UUID().uuidString.prefix(8)).md"
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-HashlineUITestDocument", fileName]
        app.launch()
        defer { app.terminate() }
        let window = app.windows[fileName]
        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.typeText("# Title")

        let book = window.toolbars.buttons["Reading Mode"]
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        book.click()
        let hidden = NSPredicate(format: "exists == false")
        expectation(for: hidden, evaluatedWith: textView)
        waitForExpectations(timeout: 3)
        book.click()
        XCTAssertTrue(textView.waitForExistence(timeout: 3), "The editor comes back")
    }
}
