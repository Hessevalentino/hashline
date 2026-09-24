import XCTest

/// Library panel: new document in the library opens as a tab, content search ignores
/// diacritics, clicking a result switches to that document.
final class LibraryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testNewDocumentSearchAndOpen() throws {
        let library = "lib-\(UUID().uuidString.prefix(8))"
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-HashlineLibraryFolder", library,
                               "-showsLibrary", "YES", "-sidebarTab", "documents",
                               "-HashlineUITestDocument", "\(library)/first.md"]
        app.launch()
        defer { app.terminate() }

        let first = app.windows["first.md"]
        let firstText = first.textViews.firstMatch
        XCTAssertTrue(firstText.waitForExistence(timeout: 5))
        firstText.typeText("# První\n\nPříliš žluťoučký kůň")
        app.typeKey("s", modifierFlags: .command)

        // New document in the library: created without a save panel, opened as a tab.
        app.typeKey("n", modifierFlags: [.command, .option])
        let second = app.windows["Untitled.md"]
        XCTAssertTrue(second.waitForExistence(timeout: 5), "New library document did not open")
        let tabs = app.windows.firstMatch.tabGroups.firstMatch.buttons.matching(identifier: "_XCUI:CloseWindow")
        let closeButtons = app.windows.firstMatch.tabGroups.firstMatch.buttons.matching(
            NSPredicate(format: "title == 'Close tab'"))
        XCTAssertEqual(app.tabGroups.count, 1, "Documents share one window as tabs")
        XCTAssertEqual(closeButtons.count + tabs.count, 2, "Two tabs")
        second.textViews.firstMatch.typeText("# Druhý")
        app.typeKey("s", modifierFlags: .command)

        // Search by content without diacritics.
        let search = second.textFields["Search title or text"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("zlutoucky")
        let hit = second.staticTexts["Příliš žluťoučký kůň"]
        XCTAssertTrue(hit.waitForExistence(timeout: 5), "Content search did not find the document")

        hit.click()
        XCTAssertTrue(app.windows["first.md"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.firstMatch.title, "first.md", "Clicking a result shows that document")
    }
}
