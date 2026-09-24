import XCTest

/// Tab in a table formats it, adds a row at the end and moves into its first cell.
final class TableUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTabFormatsAndAddsRow() throws {
        let fileName = "table-\(UUID().uuidString.prefix(8)).md"
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-HashlineUITestDocument", fileName,
                               "-showsLibrary", "NO"]
        app.launch()
        defer { app.terminate() }
        let textView = app.windows[fileName].textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))

        textView.typeText("| a | b |\n|---|---|\n| 1 | 2 |")
        textView.typeKey(.tab, modifierFlags: [])
        textView.typeText("x")
        // Typing fills the cell; the next Tab realigns the table.
        XCTAssertEqual(textView.value as? String, "| a   | b   |\n|-----|-----|\n| 1   | 2   |\n| x    |     |")

        app.typeKey("z", modifierFlags: .command)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(textView.value as? String, "| a | b |\n|---|---|\n| 1 | 2 |", "Tab is one undo step")
    }
}
