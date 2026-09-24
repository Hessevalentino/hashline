import XCTest

/// F6: regex find and replace, outline, find in library, Quick Open.
final class NavigationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFindReplaceOutlineLibrarySearchAndQuickOpen() throws {
        let library = "nav-\(UUID().uuidString.prefix(8))"
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-HashlineLibraryFolder", library,
                               "-showsLibrary", "YES", "-HashlineUITestDocument", "\(library)/first.md"]
        app.launch()
        defer { app.terminate() }

        let window = app.windows["first.md"]
        let textView = window.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))
        textView.typeText("# Alpha\n\ndate 2026-09-24 and 2025-01-02\n\n## Beta\n\nPříliš žluťoučký kůň")

        try checkRegexReplace(app: app, window: window, textView: textView)
        try checkOutlineSearchAndQuickOpen(app: app, window: window, textView: textView)
    }

    /// Regex replace with groups, all matches as one undo step.
    @MainActor
    private func checkRegexReplace(app: XCUIApplication, window: XCUIElement, textView: XCUIElement) throws {
        app.typeKey("f", modifierFlags: [.command, .option])  // Edit ▸ Find ▸ Find and Replace…
        let findField = window.textFields["findField"]
        XCTAssertTrue(findField.waitForExistence(timeout: 3))
        window.checkBoxes["findRegex"].click()
        findField.click()
        findField.typeText(#"(\d{4})-(\d\d)-(\d\d)"#)
        XCTAssertTrue(window.staticTexts["2 found"].waitForExistence(timeout: 3)
                      || window.staticTexts["1 of 2"].waitForExistence(timeout: 1))
        let replaceField = window.textFields["replaceField"]
        replaceField.click()
        replaceField.typeText("$3.$2.$1")
        window.buttons["All"].click()
        XCTAssertEqual(textView.value as? String,
                       "# Alpha\n\ndate 24.09.2026 and 02.01.2025\n\n## Beta\n\nPříliš žluťoučký kůň")
        textView.click()  // ⌘Z in the replace field would undo its own typing
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue((textView.value as? String)?.contains("2026-09-24 and 2025-01-02") == true,
                      "Replace All undoes in one step")
        window.buttons["Done"].click()
        XCTAssertFalse(findField.exists)
    }

    /// Outline (a click moves the caret to the heading), find in library, Quick Open.
    @MainActor
    private func checkOutlineSearchAndQuickOpen(app: XCUIApplication, window: XCUIElement,
                                                textView: XCUIElement) throws {
        window.radioButtons["Outline"].click()
        let beta = window.buttons["Beta"]
        XCTAssertTrue(beta.waitForExistence(timeout: 3))
        XCTAssertTrue(window.buttons["Alpha"].exists)
        beta.click()
        textView.typeText("X")
        XCTAssertTrue((textView.value as? String)?.contains("X## Beta") == true, "Outline jumps to the heading")
        app.typeKey("z", modifierFlags: .command)
        app.typeKey("s", modifierFlags: .command)

        // Find in library.
        app.typeKey("f", modifierFlags: [.command, .shift])
        let folderField = window.textFields["folderSearchField"]
        XCTAssertTrue(folderField.waitForExistence(timeout: 3))
        folderField.typeText("zlutoucky")
        XCTAssertTrue(window.staticTexts["first.md"].waitForExistence(timeout: 5), "File header of the result")

        // Quick Open from another document.
        app.typeKey("n", modifierFlags: [.command, .option])
        let second = app.windows["Untitled.md"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        app.typeKey("p", modifierFlags: .command)
        let quickOpen = app.textFields["quickOpenField"]
        XCTAssertTrue(quickOpen.waitForExistence(timeout: 3))
        quickOpen.typeText("alpha\n")
        let first = NSPredicate(format: "title == 'first.md'")
        expectation(for: first, evaluatedWith: app.windows.firstMatch)
        waitForExpectations(timeout: 5)
    }
}
